# This script collects latest midtier logs only and configuration files for Application Servers, Web Servers, and
# Cache Locator, Active MQ and WIPS services.
# It creates a "log bundle" tgz or zip file that is stored in user-specified temp directory.
###############
# NOTE: This script only works for SAS 9.4x.
###############
#
# Copyright 2023 SAS Institute, Inc.

#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#    http://www.apache.org/licenses/LICENSE-2.0
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

# PREREQUISITE:
#Make sure to have at least 5GB free space in specified temp directory

# Usage:
#1. .\collect_latest_midtier_logs_configs_s9.ps1


### GET USER INPUTS
# Get "latest" or "all" logs switch, sasconfigdir, and working temp dir as inputs
# t=logs to collect <latest|all>, d=sas config directory location (include LevN) [required], w=script work directory (user should have read/write here) [required]
param($t,[Parameter(Mandatory=$true)]$d,[Parameter(Mandatory=$true)]$w)



### DEFINE FUNCTIONS
## CHECK FREE SPACE ON TEMP DIRECTORY'S DISK
# Pass the number of GB free space you are requiring the user to have (as integer) when invoking this function
function checking_free_space($requiredfreespace) {
	$DRIVELETTER=$templogsdir.substring(0,1) #take first character of user-provided tempdir path so we know disk drive letter in Windows (used to verify available space and that it actually exists)
	If ( $DRIVELETTER -notmatch '[a-zA-Z]' ) { #if the substr is not a,B,C,d,E,F,g, [etc...]
		Write-Host "ERROR: Provided work directory could not be mapped to a Windows drive letter."
		Write-Host "ERROR: Please ensure you have specified a location on local disk."
		exit
	}
	Else {
		[uint64]$FREEBYTES = Get-Volume -DriveLetter $DRIVELETTER | Select-Object -ExpandProperty SizeRemaining #pull free disk space in bytes, uint64 safe up to 18.44 Exabytes
		$FREEGBYTES = [math]::round($FREEBYTES / 1GB,2) #convert to gigabytes and round to 2 decimals for better user display
		If ( $FREEGBYTES -ge $requiredfreespace ) {
			Write-Host "INFO: Working directory verified. Available space: $FREEGBYTES GB"
		}
		Else {
			#multi-function failure state...
			#if avail space < required free space, go here
			#if user gave us a disk that does not exist, we would get null value when pulling freebytes, and end up here because null fails to be >= int
			Write-Host "ERROR: Disk unavailable or insufficient free space on drive containing work directory $templogsdir"
			Write-Host "ERROR: Verify this is an accessible local disk with at least $requiredfreespace GB free."
			exit
		}
	}
}

## CHECK WORK / TEMP DIR READABLE AND WRITABLE
function tmp_permissions {
	If (-Not (Test-Path -Path $templogsdir) ) {
		#if can't read user-specified dir
		Write-Host "ERROR: Specified work path is not a directory or was unable to be read. Verify read permissions."
		exit
	}
	Else {
		#make our temp dir to work on files in this session
		New-Item -Path "$templogsdir" -Name "SASLogsBackupTemp-$rundatetime" -ItemType "directory"
		If (Test-Path -Path $templogsdir\SASLogsBackupTemp-$rundatetime) { #if we could make working dir
			$script:WORKDIRFULL = "$templogsdir\SASLogsBackupTemp-$rundatetime" #set var $WORKDIRFULL for actual working directory and make accessible to this script's other functions
			New-Item -Path "$WORKDIRFULL\scriptLogFile.log"
			If (Test-Path -Path $WORKDIRFULL\scriptLogFile.log -PathType leaf) { #if we could write inside working dir
				Set-Content "$WORKDIRFULL\scriptLogFile.log" "INFO: Validations completed for run initialized at $rundatetime. Starting log collection." #logfile header
				$script:SCRIPTLOG = "$WORKDIRFULL\scriptLogFile.log" #set var to reference logfile
				#Write-Host "INFO: Created log backup work directory $WORKDIRFULL" | Tee-Object -FilePath $SCRIPTLOG #debug, will overwrite contents of scriptlog file
			}
			Else { #if we could not write inside our work dir
				Write-Host "ERROR: Failed to create log file inside work directory. Verify write permissions."
				Write-Host "ERROR: Attempted write on file path: $WORKDIRFULL\scriptLogFile.log"
				exit
			}
		}
		Else {
			#if we can't read the dir we tried to make, must have not been writable
			Write-Host "ERROR: Failed to create log backup work directory. Verify write permissions."
			Write-Host "ERROR: Attempted work directory path: $templogsdir\SASLogsBackupTemp-$rundatetime"
			exit
		}
	}
}

##WEB APPLICATION SERVERS
function collect_web_app_srv_logs($getalllogs) {
	Write-Host "INFO: Collecting Web Application Server logs"
	$WEBAPPSVR="$sasconfigdir\Web\WebAppServer"
	New-Item -Path "$WORKDIRFULL\" -Name "WebAppServer" -ItemType "directory"
	
	Get-ChildItem -Path $WEBAPPSVR -Directory | ForEach-Object {                 #locates each existing SASServerX_Y instance and then iterate over them
		$WASNUMNAME = $_.Name #name of webappserver only ("SASServer1_1")
		$WASNUMPATH = $_.FullName #complete folder path to each webapp server instance (C:\SAS\Config\Lev1\Web\WebAppServer\SASServer1_1\, ....\2_1\, etc)
		#Write-Host "Name: $WASNUMNAME ...... Path: $WASNUMPATH" #debug
		
		Write-Host "INFO: Creating directories for $WASNUMNAME logs and config files."
		New-Item -Path "$WORKDIRFULL\WebAppServer\" -Name "$WASNUMNAME" -ItemType "directory" #....\WebAppServer\SASServer1_1
		New-Item -Path "$WORKDIRFULL\WebAppServer\$WASNUMNAME\" -Name "ServerLogs" -ItemType "directory" #....\WebAppServer\SASServer1_1\ServerLogs
		New-Item -Path "$WORKDIRFULL\WebAppServer\$WASNUMNAME\" -Name "AppLogs" -ItemType "directory" #....\WebAppServer\SASServer1_1\AppLogs
		New-Item -Path "$WORKDIRFULL\WebAppServer\$WASNUMNAME\" -Name "config" -ItemType "directory" #....\WebAppServer\SASServer1_1\config
		
		Write-Host "INFO: Copying $WASNUMNAME Server logs"
		If ($getalllogs -eq 1) {
			#all
			Get-ChildItem -Path $WASNUMPATH\logs\* | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\ServerLogs"		
		}
		Else {
			#latest
			Get-ChildItem -Path $WASNUMPATH\logs\server.log | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\ServerLogs"
			Get-ChildItem -Path $WASNUMPATH\logs\catalina.out | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\ServerLogs"	
			Get-ChildItem -Path $WASNUMPATH\logs\gemfire.log | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\ServerLogs"	
		}
		
		Write-Host "INFO: Copying $WASNUMNAME Web Application logs"
		If ($getalllogs -eq 1) {
			#all
			Get-ChildItem -Path $sasconfigdir\Web\Logs\$WASNUMNAME\* | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\AppLogs"	
		}
		Else {
			#latest
			Get-ChildItem -Path $sasconfigdir\Web\Logs\$WASNUMNAME\*.log | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\AppLogs"	
		}

		Write-Host "INFO: Copying $WASNUMNAME configuration files" #NOTE: Source .sh script does NOT have a different set of files collected for this piece regardless of latest/all, so replicating that here...
		If ($getalllogs -eq 1) {
			#all
			Get-ChildItem -Path $WASNUMPATH\conf\server.xml | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\conf\jaas.config | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\conf\catalina.properties | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\conf\web.xml | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\bin\setenv.bat | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
		}
		Else {
			#latest
			Get-ChildItem -Path $WASNUMPATH\conf\server.xml | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\conf\jaas.config | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\conf\catalina.properties | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\conf\web.xml | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
			Get-ChildItem -Path $WASNUMPATH\bin\setenv.bat | Copy-Item -Destination "$WORKDIRFULL\WebAppServer\$WASNUMNAME\config"
		}
	}
}


##WEB SERVER

#SAS Web Server logs
function collect_web_srv_logs($getalllogs) {
  Write-Host "INFO: Copying SAS Web Server Logs"
  New-Item -Path "$WORKDIRFULL\" -Name "WebServer" -ItemType "directory"
  If ($getalllogs -eq 1) {
	  	Get-ChildItem -Path $sasconfigdir\Web\WebServer\logs\* | Copy-Item -Destination "$WORKDIRFULL\WebServer"

	}
	Else {
		Get-ChildItem -Path $sasconfigdir\Web\WebServer\logs\access*.log | Copy-Item -Destination "$WORKDIRFULL\WebServer"
		Get-ChildItem -Path $sasconfigdir\Web\WebServer\logs\error*.log | Copy-Item -Destination "$WORKDIRFULL\WebServer"
		Get-ChildItem -Path $sasconfigdir\Web\WebServer\logs\ssl_request*.log | Copy-Item -Destination "$WORKDIRFULL\WebServer"
	}
}


#SAS Web Server configuration files
function collect_web_srv_configs {
	Write-Host "INFO: Copying Web Server configuration files"
	#New-Item -Path "$WORKDIRFULL\" -Name "WebServer" -ItemType "directory" #this function runs after collect_web_srv_logs, so this directory should always exist. Leave this commented out unless that is no longer true.
	Get-ChildItem -Path $sasconfigdir\Web\WebServer\conf\httpd.conf | Copy-Item -Destination "$WORKDIRFULL\WebServer"
	Get-ChildItem -Path $sasconfigdir\Web\WebServer\conf\sas.conf | Copy-Item -Destination "$WORKDIRFULL\WebServer"
	Get-ChildItem -Path $sasconfigdir\Web\WebServer\conf\extra\httpd-ssl.conf | Copy-Item -Destination "$WORKDIRFULL\WebServer"
}


##ActiveMQ
function collect_activemq_logs($getalllogs) {
	#this uses $getalllogs, because logs to collect changes if we want "all" or only the "latest" logfiles
	New-Item -Path "$WORKDIRFULL\" -Name "activemq" -ItemType "directory" #make dir for backup files
	If ($getalllogs -eq 1) {
		#all logs
		Get-ChildItem -Path $sasconfigdir\Web\activemq\data\*.log* | Copy-Item -Destination "$WORKDIRFULL\activemq" #move items
	}
	Else {
		#latest only ($getalllogs -eq 0); default
		Get-ChildItem -Path $sasconfigdir\Web\activemq\data\activemq.log | Copy-Item -Destination "$WORKDIRFULL\activemq"
	}
}

function collect_activemq_configs {
	#this does NOT use $getalllogs, because the log to collect does not change regardless of if we are getting all logs or only latest logs
	Write-Host "INFO: Copying Active MQ configuration file"
	Get-ChildItem -Path $sasconfigdir\Web\activemq\conf\activemq.xml | Copy-Item -Destination "$WORKDIRFULL\activemq" #move items
}


##Cache Locator
function collect_gemfire_logs($getalllogs) {
	Write-Host  "INFO: Copying Cache Locator Logs"

	# 2025-12-05 gw Need to tolerate instance IDs other than ins_41415.

	# Get a list of paths that match the pattern $sasconfigdir\Web\{gemfire|geode}\instances\ins_*
	$instancePaths = Get-ChildItem -Path "$sasconfigdir\Web" -Directory | Where-Object { $_.Name -in @("gemfire", "geode") } | ForEach-Object {
		Get-ChildItem -Path "$($_.FullName)\instances" -Directory | Where-Object { $_.Name -like "ins_*" }
	}

	# If at least one instance path is found, we will loop through each. Otherwise we will log a warning and exit the function.
	If ($instancePaths.Count -gt 0) {
		foreach ($instance in $instancePaths) {
			$instanceType = $instance.Parent.Parent.Name  # gemfire or geode
			$instanceName = $instance.Name                # ins_XXXX
			$chlocpath = $instance.FullName               # Full path to the instance
			Write-Host "INFO: Found $instanceType instance: $instanceName at path: $chlocpath" #debug
			New-Item -Path "$WORKDIRFULL\" -Name "$instanceType-$instanceName" -ItemType "directory"
			If ($getalllogs -eq 1) {
				Get-ChildItem -Path "$chlocpath\*.log" | Copy-Item -Destination "$WORKDIRFULL\$instanceType-$instanceName"
			}
			Else {
				Get-ChildItem -Path "$chlocpath\gemfire.log" | Copy-Item -Destination "$WORKDIRFULL\$instanceType-$instanceName"
			}
		}
	}
	Else {
		Write-Host "WARN: No Gemfire or Geode instances found under $sasconfigdir\Web\{gemfire|geode}\instances\ins_*."
		Write-Host "WARN: No cache locator logs will be collected."
		# Create a placeholder directory to indicate no logs were collected
		New-Item -Path "$WORKDIRFULL\" -Name "cachelocator" -ItemType "directory"
		New-Item "$WORKDIRFULL\cachelocator\cache-locator-no-instances-found.txt"
		Set-Content "$WORKDIRFULL\cachelocator\cache-locator-no-instances-found.txt" "No Gemfire or Geode instances were found under $sasconfigdir\Web\{gemfire|geode}\instances\ins_*. No logs were collected for Cache Locator."
	}

}


##WEB INFRASTRUCTURE PLATFORM DATA SERVER
function collect_wipds_configs {
	Write-Host "INFO: Copying Web Infrastructure Platform Data Server configuration file"
	New-Item -Path "$WORKDIRFULL\" -Name "wipds" -ItemType "directory"
	Get-ChildItem -Path $sasconfigdir\WebInfrastructurePlatformDataServer\data\postgresql.conf | Copy-Item -Destination "$WORKDIRFULL\wipds"
}


##CREATE LOG BUNDLE ZIP
#Prefer TAR as powershell ZIP max filesize is only 2GB.
#TAR available by default since Win10 Build 17063 (released early 2018)
#Check and attempt zip if tar is not available; if too big to zip then tell user to do it manually
function create_log_bundle {
	Write-Host "INFO: Attempting to compress log bundle..."
	If (Get-Command tar -ErrorAction SilentlyContinue) {
		Write-Host "INFO: Located TAR executable. Generating .tgz..."
		cd $WORKDIRFULL
		tar -cvzf $templogsdir\log-bundle-$rundatetime.tgz *
		cd $userexecdir
		$USERINSTRUCTEND1 = "INFO: Log bundle has been saved as $templogsdir\log-bundle-$rundatetime.tgz"
		$USERINSTRUCTEND2 = "INFO: Please upload the log bundle file to SAS Technical Support via your current track."
	}
	Else {
		Write-Host "WARN: Could not locate TAR executable in PATH. Checking fallback PowerShell ZIP utility..."
		[uint64]$BIGGESTFILE = Get-ChildItem $WORKDIRFULL | Measure-Object -Property Length -maximum | Select-Object -expand Maximum #determine size of largest file in archive
		If ($BIGGESTFILE -lt 2147483648) { #if no files over 2GB limit of powershell zip builtin
			Write-Host "INFO: Archive can be created using ZIP utility. Generating .zip..."
			Compress-Archive -Path "$WORKDIRFULL\*" -DestinationPath "$templogsdir\log-bundle-$rundatetime.zip"
			$USERINSTRUCTEND1 = "INFO: Log bundle has been saved as $templogsdir\log-bundle-$rundatetime.zip"
			$USERINSTRUCTEND2 = "INFO: Please upload the log bundle file to SAS Technical Support via your current track."
		}
		Else { #at least one file was determined to be too big to zip, user will need to do it manually
			Write-Host "ERROR: File(s) in the log bundle are too large to be zipped by the PowerShell built-in utility."
			Write-Host "WARN: Log bundle has been saved but not compressed."
			$USERINSTRUCTEND1 = "WARN: Please navigate to $templogsdir using Windows Explorer. Right-click subdirectory SASLogsBackupTemp-$rundatetime and create a .zip of it manually."
			$USERINSTRUCTEND2 = "INFO: After zipping the log bundle file, please upload to SAS Technical Support via your current track."
		}
	}
	Write-Host ""
	Write-Host ""
	Write-Host ""
	Write-Host $USERINSTRUCTEND1 -BackgroundColor Magenta -ForegroundColor Black
	Write-Host $USERINSTRUCTEND2 -BackgroundColor Magenta -ForegroundColor Yellow
	#successful end of script
}


### INITIALIZE
## VALIDATE USER INPUTS
$sasconfigdir = $d #rename user-provided params for clarity in later use
$templogsdir = $w
$rundatetime = Get-Date -Format yyyyMMdd_HHmmss #save run date-time as string
$userexecdir = $pwd #save the current dir, this has to be changed in the script to make the archive file correctly; retain so we can set it back afterward
$ErrorActionPreference = "SilentlyContinue" #suppress PS errors when files do not exist, as this is handled internally

If (Test-Path -Path $sasconfigdir\ConfigData\status.xml -PathType leaf) {
	Write-Host "INFO: Verified SAS Configuration Directory path, using $sasconfigdir for this run."
}

ElseIf ( $sasconfigdir -eq "" ) {
	# If user did not provide a sasconfig Directory
	Write-Host "ERROR: No SAS Configuration Directory path was specified."
	exit
}
Else {
	# If the status.xml file does not exist under provided sasconfigdir path, probably not actually a sasconfig dir
	Write-Host "ERROR: Unable to determine if provided folder path contains a SAS Configuration Directory."
	Write-Host "ERROR: Verify that the provided path is correct and includes the LevN."
	Write-Host "ERROR: Example: C:\SAS\Config\Lev1"
	Write-Host "ERROR: Also verify the user running this script has read permissions to the location and subfolders."
	exit
}

If ( $t -eq 'all' ) {
    $script:getalllogs=1 #if logs being collected will vary between "latest" and "all", you can set $getalllogs as an input parameter for those logs' collection function within this script. Then use a root-level if/else to change logic and collect either all logs (1) or only certain ones (0). If logs to collect do not change between latest and all, simply do not reference this input parameter on the function. For examples, refer to the activemq collection functions within this script.
	Write-Host "INFO: Collecting ALL logs for this run due to -t=all option specified."
	checking_free_space 5 #5GB free space will be validated
	tmp_permissions
	collect_web_app_srv_logs $getalllogs
	collect_web_srv_logs $getalllogs
	collect_web_srv_configs
	collect_activemq_logs $getalllogs #this uses $getalllogs
	collect_activemq_configs #this does NOT use $getalllogs
	collect_gemfire_logs $getalllogs
	collect_wipds_configs
	create_log_bundle
}
ElseIf ($t -eq 'latest' -Or $t -eq $null ) {
	#Default behavior.
	$script:getalllogs=0 #See note about $getalllogs in parent IF
	Write-Host "INFO: Collecting only latest available logs for this run."
	checking_free_space 1 #1GB
	tmp_permissions
	collect_web_app_srv_logs $getalllogs
	collect_web_srv_logs $getalllogs
	collect_web_srv_configs
	collect_activemq_logs $getalllogs
	collect_activemq_configs
	collect_gemfire_logs $getalllogs
	collect_wipds_configs
	create_log_bundle
}
Else {
	Write-Host "ERROR: Log collection flag not specified correctly, please check -t parameter input or remove from command."
}