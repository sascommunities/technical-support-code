#!/bin/bash

# Linux Bash Script that runs the SAS Content Assessment applications inventoryContent, profileContent, gatherSASCode, codeCheck, i18nCodeCheck, and publishAssessedContent.
# Date: 31MAR2025

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Set your path to the unpacked SAS 9 Content Assessment files and the location to log output from this script
catpath="/opt/sasinside/contentassessment"

# END OF CUSTOM VARIABLE SETUP

# Set a timestamp for the output
timestamp=$(date +"%Y%m%d - %H.%M.%S")


# a function to call and check for errors
check_and_call() {
	echo calling:  "$@"
    "$@"
    if [ $? -ne 0 ]; then
        echo "Error Detected: abort"
        exit 1
    fi
}


echo
echo "Running: $(basename "$0")"
echo "catpath = $catpath"
echo "Time: $timestamp"
echo "  -Please wait...."

echo
echo "############################################################################"
echo "# INVENTORY                                                                #"
echo "############################################################################"
echo
check_and_call "$catpath/assessment/inventoryContent"

echo
echo "############################################################################"
echo "# PROFILE                                                                  #"
echo "############################################################################"
echo
check_and_call "$catpath/assessment/profileContent"
echo
echo "############################################################################"
echo "# GATHER SAS CODE                                                          #"
echo "############################################################################"
echo
check_and_call "$catpath/assessment/gatherSASCode" --all

echo
echo "############################################################################"
echo "# CODE CHECK                                                               #"
echo "############################################################################"
echo
echo "########### Running SASObjCode - $catpath/assessment/gatheredSASCode"
echo
check_and_call "$catpath/assessment/codeCheck" --scan-tag SASObjCode --source-location "$catpath/assessment/gatheredSASCode"
echo
echo "########### Running BaseSASCode - $catpath/assessment/pathslist.txt"
echo
check_and_call "$catpath/assessment/codeCheck" --scan-tag BaseSASCode --sources-file "$catpath/assessment/pathslist.txt"

echo
echo "############################################################################"
echo "# CODE CHECK FOR INTERNATIONALIZATION                                      #"
echo "############################################################################"
echo
echo "########### Running SASObjCode - $catpath/assessment/gatheredSASCode"
echo
check_and_call "$catpath/assessment/i18nCodeCheck" --scan-tag SASObjCode --source-location "$catpath/assessment/gatheredSASCode"
echo
echo "########### Running BaseSASCode - $catpath/assessment/pathslist.txt"
echo
check_and_call "$catpath/assessment/i18nCodeCheck" --scan-tag BaseSASCode --sources-file "$catpath/assessment/pathslist.txt"

echo
echo "############################################################################"
echo "# PUBLISH                                                                  #"
echo "############################################################################"
echo
check_and_call "$catpath/assessment/publishAssessedContent" --create-uploads --datamart-type inventory --encrypt-aes
check_and_call "$catpath/assessment/publishAssessedContent" --create-uploads --datamart-type profile --encrypt-aes
check_and_call "$catpath/assessment/publishAssessedContent" --create-uploads --datamart-type codecheck --encrypt-aes
check_and_call "$catpath/assessment/publishAssessedContent" --create-uploads --datamart-type i18n --encrypt-aes

# set completion message
if [ $? -eq 0 ]; then
    catscriptmsg="SUCCESS"
else
    catscriptmsg="ERROR"
fi

echo
echo "############################################################################"
echo "# SAS Content Assessment $catscriptmsg                                      #"
echo "############################################################################"