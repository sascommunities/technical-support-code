#!/bin/bash

# This script allows for the automation of running the 
# SAS Hot Fix Analysis, Download and Deployment Tool (SASHFADD)
# to generate a hot fix report and optionally send it to a provided 
# email address
# Date: 08DEC2021

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Script to automate SASHFADD
#
# This script automates the process of running SASHFADD. It performs the following steps.
# 1. If UPDATEHFADD is set to 1, it will download SASHFADD. Replacing an existing installation if one is present.
#    If an existing installation is present it will take a backup of SASHFADD.cfg
#    It will apply the options specified under Step 1's "Add configuration options" section.
# 2. It will generate a Deployment Registry using sas.tools.viewregistry.jar in SASHOME/deploymntreg and copy it to the supplied SASHFADD path
# 3. It will run SASHFADD
# 4. If SENDNOTIFY is set to 1, it will email the Analysis HTML file to the supplied NOTIFYEMAIL, from the supplied FROMEMAIL, using the mail command.

# Specify the environment variables used by the script.
# SASHFADD is the path to look for / install SASHFADD
# SASHOME is the SAS Installation Directory it should perform the analysis against
# UPDATEHFADD, if set to 1, will download SASHFADD from SAS and (if present) replace the existing installation in the SASHFADD path with the new one.
# SENDNOTIFY, if set to 1, will instruct the script to send an email with the SASHFADD analysis attached.
# NOTIFYEMAIL is the email address where the email referenced above should be sent
# FROMEMAIL is the email address the email referenced above should be sent from

SASHFADD="<SASHFADD-installation-directory>"
SASHOME="<sas-installation-directory>"
NOTIFYEMAIL=admin@example.com
FROMEMAIL=no-reply@example.com
UPDATEHFADD=1
SENDNOTIFY=1

############
# End Edit #
############

echo ""
echo "NOTE: Checking if $SASHFADD exists."
if [ -d $SASHFADD ]
	then echo "NOTE: Using $SASHFADD as SASHFADD installation path."
	else 
		echo "ERROR: SASHFADD=$SASHFADD does not exist."
		exit 2
fi
echo ""
echo "NOTE: Checking if $SASHOME exists and is a valid SAS Installation Directory."
if [ -d $SASHOME ]
	then
		if [ -d $SASHOME/deploymntreg ]
			then echo "NOTE: $SASHOME/deploymntreg exists. Using $SASHOME as SAS Installation Directory."
			else 
				echo "ERROR: $SASHOME does not appear to be a valid SAS installation directory (no $SASHOME/deploymntreg path)"
				exit 2
		fi
	else 
		echo "ERROR: SASHOME=$SASHOME does not exist."
fi
echo ""
if [ $UPDATEHFADD = 1 ] 
	then 
		echo "NOTE: UPDATEHFADD set to 1, will download SASHFADD from SAS"
fi
if [ $SENDNOTIFY = 1 ]
	then 
		echo "NOTE: SENDNOTIFY set to 1, will send the analysis via email."
		echo "NOTE: Confirming mail command is available."
		which mail > /dev/null 2>&1
		status=$?

		if [ $status -ne 0 ] 
			then 
				echo "ERROR: mail command does not appear to be installed. Install the mailx package."
				exit 2
			else echo "NOTE: Using ${NOTIFYEMAIL} to send analysis from ${FROMEMAIL}."
		fi
fi
echo ""
echo "NOTE: Checking for the presence of /usr/local/bin/perl5 to allow SASHFADDux.pl to run."

if [ -f /usr/local/bin/perl5 ]
	then echo "NOTE: Found perl in /usr/local/bin/perl5"
	else 
		echo "ERROR: Perl not in /usr/local/bin/perl5"
		echo "Ensure perl 5 is installed (perl --version). If so, add a link to it's path: ln -s \$(which perl) /usr/local/bin/perl5"
		exit 2
fi

echo ""
echo "NOTE: Checking if curl is installed."
which curl > /dev/null 2>&1
status=$?

if [ $status -ne 0 ]
	then
		echo "ERROR: curl does not appear to be installed. SASHFADD requires curl."
		exit 2
	else echo "NOTE: curl appears to be installed."
fi

#############################################
# Step 1. Update SASHFADD to latest version #
#############################################

if [ $UPDATEHFADD = 1 ]
	then
		echo ""
		echo "NOTE: Downloading latest SASHFADD from SAS."
		echo ""
		# Download current version of SASHFADD
	
		if curl https://tshf.sas.com/techsup/download/hotfix/HF2/util01/SASHotFixDLM/tool/SASHFADDux.tar -o $SASHFADD/SASHFADDux.tar
			then echo "NOTE: Download successful."
			else 
				echo "ERROR: Download failed."
				exit 2
		fi

		echo "NOTE: Checking to see if SASHFADD.pl is already present."

		if [ -f $SASHFADD/SASHFADD.pl ]
			then
				echo "NOTE: SASHFADD.pl is present. Checking for configuration file."
				echo ""
				if [ -f $SASHFADD/SASHFADD.cfg ]
					then
						echo "NOTE: Backing up SASHFADD.cfg"
						mv $SASHFADD/SASHFADD.cfg $SASHFADD/SASHFADD.cfg."$(date +%Y-%m-%d_%H%M%S)"
					else echo "WARNING: No existing SASHFADD.cfg was found to back up."
				fi
				echo "NOTE: Removing existing SASHFADD."
				# Remove existing .pl file
				rm $SASHFADD/SASHFADD.pl
		fi

		echo ""
		echo "NOTE: Extracting newly downloaded SASHFADDux.tar and deleting tar file."

		# Extract tar file
		tar -C $SASHFADD -xf $SASHFADD/SASHFADDux.tar && rm $SASHFADD/SASHFADDux.tar

		echo ""
		echo "NOTE: Uncommenting options to SASHFADD"

		# Add configuration options

		echo "Uncommenting -SILENT"
		sed -i 's/# -SILENT/-SILENT/' $SASHFADD/SASHFADD.cfg

		echo "Uncommenting -ENGLISH_ONLY"
		sed -i 's/# -ENGLISH_ONLY/-ENGLISH_ONLY/' $SASHFADD/SASHFADD.cfg

		echo "Uncommenting -SAS 9.4"
		sed -i 's/# -SAS 9.4/-SAS 9.4/' $SASHFADD/SASHFADD.cfg

fi

########################################
# Step 2. Generate deployment registry #
########################################
echo ""
echo "NOTE: Switching to path $SASHOME/deploymntreg"
# Change to deploymntreg directory
cd $SASHOME/deploymntreg || { echo "ERROR: Change Directory failed."; exit 1; } 
echo "NOTE: Generating deployment registry"
# Run sas.tools.viewregistry.jar using SAS private JRE
$SASHOME/SASPrivateJavaRuntimeEnvironment/9.4/jre/bin/java -jar sas.tools.viewregistry.jar
echo "NOTE: Copying registry to $SASHFADD"
# Copy deployment registry to SASHFADD path
cp -p $SASHOME/deploymntreg/DeploymentRegistry.txt $SASHFADD/DeploymentRegistry.txt

########################
# Step 3. Run SASHFADD #
########################
echo ""
echo "NOTE: Switching to path $SASHFADD"
echo "NOTE: Running SASHFADD.pl, redirecting output to SASHFADD.out"
cd $SASHFADD || { echo "ERROR: Change Directory failed."; exit 1; }
./SASHFADD.pl > $SASHFADD/SASHFADD.out 2>&1

SASHFADDDIRSUFF=$(tail -2 SASHFADD.out | head -1 | cut  -f3 -d' ' | awk '{ print substr($0,10) }')

echo ""
echo "NOTE: SASHFADD analysis written to directory $SASHFADD/SASHFADD_${SASHFADDDIRSUFF}" 

#################################
# Step 4. Email analysis result #
#################################
if [ $SENDNOTIFY = 1 ]
	then
		echo ""
		echo "NOTE: Emailing analysis html file to ${NOTIFYEMAIL}"
		cat << EOF | mail -a "SASHFADD_${SASHFADDDIRSUFF}/SAS_Hot_Fix_Analysis_Report_${SASHFADDDIRSUFF}.html" -s "Analysis for $(date) on $(hostname -f)" -r ${FROMEMAIL} ${NOTIFYEMAIL}
Please find attached the hot fix analysis report for $(date) for $(hostname) on SASHome $SASHOME.
EOF
fi

###################
# Step 5. Cleanup #
###################

echo ""
echo "NOTE: Deleting SAS94_HFADD_data.xml and SAS94_HFADD_data_ftp_download.sh files generated by SASHFADD."
rm $SASHFADD/SAS94_HFADD_data_ftp_download.sh $SASHFADD/SAS94_HFADD_data.xml
echo "NOTE: Script completed."
