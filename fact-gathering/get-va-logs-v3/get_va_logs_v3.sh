#!/bin/bash
# This script collects logs related to Visual Analtyics from a Viya 3.x system.
# Date: 05DEC2024
#
# Copyright © 2024, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Set your Viya deployment name (replace 'viya' with your actual deployment name)
DEPLOYMENT_NAME="viya"

# Specify the directory where logs are stored
LOG_DIR="/opt/sas/${DEPLOYMENT_NAME}/config/var/log"

# List of services you want to retrieve logs for (adjust as needed)
SERVICES=("sasvisualanalytics" "report-data" "reportdistribution" "report-packages" "report-renderer" "reportservicesgroup")

    read -rp $'\e[1;36mEnter your SAS Case Number:\e[0m ' csmcase
    echo
    mkdir -p "/tmp/$csmcase"
	
# Loop through each service and download its logs
for SERVICE in "${SERVICES[@]}"; do
    LOG_PATH="${LOG_DIR}/${SERVICE}/default"
# Download logs to a local directory (you can customize the destination)
    cp -rp "${LOG_PATH}" "/tmp/$csmcase/${SERVICE}"
done

echo -e "\e[1;36mThank you for contacting SAS Technical Support :\e[0m"
echo -e " "

echo -e "\e[1;32mLogs have been copied in /tmp/$csmcase , Please find name of folder and list of downloaded logs below : \e[0m"
echo -e "---------------------------------------------"

tar -zcvpf "/tmp/$csmcase.tar.gz" -C /tmp "$csmcase"
echo -e "---------------------------------------------"
echo -e " "

echo -e "\e[1;36mTar file is created of /tmp/$csmcase/ folder.\e[0m"
echo -e " "

echo -e "\e[1;32mYou can share us the /tmp/$csmcase.tar file over the Service now case or upload the same in SAS TSDrive.\e[0m"
echo -e " "

echo -e "\e[1;36mThank you, Please upload the logs here https://sas.service-now.com/csm?id=kb_article_view&sysparm_article=KB0036136\e[0m"