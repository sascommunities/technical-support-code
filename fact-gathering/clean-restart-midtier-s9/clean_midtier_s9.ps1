# This script cleans midtier node including cache locator.
# One has the option of cleaning cache locator only.
# This script backs up logs under each SAS server &
# cleans temp, work & data directories under gemfire as well as  activeMQ data.
# It is up to the user to clean hung processes after this script is run and restart midtier services.
###############
# NOTE: This script only works for SAS 9.4x.
###############

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# PREREQUISITE: Stop all midtier servers.
# Usage: 1. .\clean_midtier_s9.ps1


### GET USER INPUTS
# Get "cache locator only" switch and sasconfig directory location as inputs
# c=cache locator only <true|false>, d=sas config directory location (include LevN) [required]
param($c,[Parameter(Mandatory=$true)]$d)


### DEFINE FUNCTIONS
## GEMFIRE
function clean_gemfire {
	# For M7 and prior releases
	$GEMFIRE="$sasconfigdir\Web\gemfire\instances\ins_41415"
	# For M8
	$GEODE="$sasconfigdir\Web\geode\instances\ins_41415"
	
	If (Test-Path -Path $GEMFIRE) {
		Write-Host "Working on GEMFIRE $GEMFIRE - Cleaning..."
		Get-ChildItem -Path $GEMFIRE\*.log -Recurse | Remove-Item -Force -Recurse
		Get-ChildItem -Path $GEMFIRE\*.dat -Recurse | Remove-Item -Force -Recurse
		Get-ChildItem -Path $GEMFIRE\*.locator -Recurse | Remove-Item -Force -Recurse
		Get-ChildItem -Path $GEMFIRE\ConfigDiskDir_\* -Recurse | Remove-Item -Force -Recurse
		
	}
	ElseIf (Test-Path -Path $GEODE) {
		Write-Host "Working on $GEODE - Cleaning..."
		Get-ChildItem -Path $GEODE\*.log -Recurse | Remove-Item -Force -Recurse
		Get-ChildItem -Path $GEODE\*.dat -Recurse | Remove-Item -Force -Recurse
		Get-ChildItem -Path $GEODE\*.locator -Recurse | Remove-Item -Force -Recurse
		Get-ChildItem -Path $GEMFIRE\ConfigDiskDir*\* -Recurse | Remove-Item -Force -Recurse #dual wildcard new for M8... need to test
	}
	Else {
		Write-Host "Cache locator not found. Skipping."
	}
}

## ACTIVEMQ
function clean_activemq {
	$ACTIVEMQ="$SASCONFIGDIR\Web\activemq"
	If (Test-Path -Path $ACTIVEMQ) {
		Write-Host "Working on ACTIVEMQ  $ACTIVEMQ\data - Cleaning..."
		Get-ChildItem -Path $ACTIVEMQ\data\* | Remove-Item -Force -Recurse
	}
	Else {
		Write-Host "$ACTIVEMQ not found. Skipping."
	}
}


## WEBAPPSERVERS
# clean up the log files for the web application server instances
function clean_webappsvr {
	$WEBAPPSVR="$sasconfigdir\Web\WebAppServer"
	Get-ChildItem -Path $WEBAPPSVR -Directory | ForEach-Object {                 #locates each existing SASServerX_Y instance and then iterate over them
		$WASNUMNAME = $_.Name #name of webappserver only ("SASServer1_1")
		$WASNUMPATH = $_.FullName #complete folder path to each webapp server instance (C:\SAS\Config\Lev1\Web\WebAppServer\SASServer1_1\, ....\2_1\, etc)
		#Write-Host "Name: $WASNUMNAME ...... Path: $WASNUMPATH" #debug
		New-Item -Path "$WASNUMPATH\logs\" -Name "ServerBackup-$rundatetime" -ItemType "directory" #make dir for backup files
		If (Test-Path -Path $WASNUMPATH\logs\ServerBackup-$rundatetime) {
			Write-Host "Backing up $WASNUMNAME log files..."
			Get-ChildItem -Path $WASNUMPATH\logs\*.log | Move-Item -Destination "$WASNUMPATH\logs\ServerBackup-$rundatetime"
			Get-ChildItem -Path $WASNUMPATH\logs\*.log* | Move-Item -Destination "$WASNUMPATH\logs\ServerBackup-$rundatetime"
			Get-ChildItem -Path $WASNUMPATH\logs\*.txt | Move-Item -Destination "$WASNUMPATH\logs\ServerBackup-$rundatetime"
			Get-ChildItem -Path $WASNUMPATH\logs\*.out | Move-Item -Destination "$WASNUMPATH\logs\ServerBackup-$rundatetime"
			Write-Host "Backup saved in $WASNUMPATH ."
			Write-Host "Cleaning $WASNUMNAME temp and work files..."
			Get-ChildItem -Path $WASNUMPATH\temp\* | Remove-Item -Force -Recurse
			Get-ChildItem -Path $WASNUMPATH\work\* | Remove-Item -Force -Recurse
			New-Item -Path "$WASNUMPATH\logs\server.log" -ItemType "file" #reinit new server.log file
			}
		Else {
			Write-Host "WARN: Unable to create backup file directory for $WASNUMNAME log files!"
			Write-Host "WARN: Check write permissions under $WASNUMPATH"
			Write-Host "Skipping cleanup of Web Application Server $WASNUMNAME log files..."
			}
		}
}


## WEB APPLICATION LOGS
# clean up the log files for actual web applications (examples: SASLogon, SASStudio)
# note this is very similar to the function above for webappserver instances, but the paths are different, read carefully if editing!
function clean_webappnlogs {
	$WEBAPPNLOGS="$sasconfigdir\Web\Logs"
	Get-ChildItem -Path $WEBAPPNLOGS -Directory | ForEach-Object {
		$WALOGSNUMNAME = $_.Name #name of webappserver only ("SASServer1_1")
		$WALOGSNUMPATH = $_.FullName #complete folder path to each webapp server instance (C:\SAS\Config\Lev1\Web\Logs\SASServer1_1\, ....\2_1\, etc)
		#Write-Host "Name: $WALOGSNUMNAME ...... Path: $WALOGSNUMPATH" #debug
		New-Item -Path "$WALOGSNUMPATH" -Name "WebAppBackup-$rundatetime" -ItemType "directory"
		If (Test-Path -Path $WALOGSNUMPATH\WebAppBackup-$rundatetime) {
			Write-Host "Backing up $WALOGSNUMNAME web application log files..."
			Get-ChildItem -Path $WALOGSNUMPATH\*log* | Move-Item -Destination "$WALOGSNUMPATH\WebAppBackup-$rundatetime"
			Write-Host "Backup saved in $WALOGSNUMPATH ."
			}
		Else {
			Write-Host "WARN: Unable to create backup file directory for $WALOGSNUMNAME web application log files!"
			Write-Host "WARN: Check write permissions under $WALOGSNUMPATH"
			Write-Host "Skipping cleanup of Web Application log files for webapps hosted on $WALOGSNUMNAME..."
			}
	}
}


## WEBSERVER
function clean_webserver {
	$WEBSVR="$sasconfigdir\Web\WebServer"
	New-Item -Path "$WEBSVR\logs\" -Name "Backup-$rundatetime" -ItemType "directory"
	If (Test-Path -Path $WEBSVR\logs\Backup-$rundatetime) {
		Write-Host "Backing up web server log files..."
		Get-ChildItem -Path $WEBSVR\logs\*.log | Move-Item -Destination "$WEBSVR\logs\Backup-$rundatetime"
		Write-Host "Backup saved in $WEBSVR ."
	}
	Else {
		Write-Host "WARN: Unable to create backup file directory for web server log files!"
		Write-Host "WARN: Check write permissions under $WEBSVR\logs\"
		Write-Host "Skipping cleanup of web server log files..."
	}
}


### INITIALIZE
## VALIDATE USER INPUTS
$sasconfigdir = $d #rename user-provided cfgdir param for clarity in later use
$rundatetime = Get-Date -Format yyyyMMdd_HHmmss #save run date-time as string


If (Test-Path -Path $sasconfigdir\ConfigData\status.xml -PathType leaf) {
	Write-Host "Verified SAS Configuration Directory path, using $sasconfigdir for this run."
}
ElseIf ( $sasconfigdir -eq "" ) {
	# If user did not provide a sasconfig Directory
	Write-Host "ERROR: No SAS Configuration Directory path was specified."
	exit
}
Else {
	# If the status.xml file does not exist under provided sasconfigdir path, probably not actually a sasconfig dir
	Write-Host "ERROR: Unable to determine if provided folder path contains a SAS Configuration Directory."
	Write-Host "Verify that the provided path is correct and includes the LevN."
	Write-Host "Example: C:\SAS\Config\Lev1"
	Write-Host "Also verify the user running this script has read permissions to the location and subfolders."
	exit
}

If ( $c -eq 'true' ) {
    $cachelocatoronly=1
	Write-Host "Cache Locator ONLY flag specified. Only working on Cache Locator files for this run."
	clean_gemfire
}
ElseIf ($c -eq 'false' -Or $c -eq $null ) {
	$cachelocatoronly=0
	Write-Host "No Cache Locator flag specified, running on all files." #debug
	clean_activemq
	clean_gemfire
	clean_webappsvr
	clean_webappnlogs
	clean_webserver
}
Else {
	Write-Host "Cache locator flag is not specified correctly, please check command."
}