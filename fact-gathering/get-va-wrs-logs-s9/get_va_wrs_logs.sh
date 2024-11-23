#!/bin/bash
# This script collects logs from Mid-tier/VAAR node including Web Logs related to VA & WRS.
# Date: 03JUN2024
#
# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# NOTE: This script only works for SAS 9.4 (Mid-tier/VAAR server)  & should only be used under SAS Administrator's supervision.
#
###############
# SAS INSTITUTE INC. IS PROVIDING YOU WITH THE COMPUTER SOFTWARE CODE INCLUDED WITH THIS AGREEMENT ("CODE")
# ON AN "AS IS" BASIS, AND AUTHORIZES YOU TO USE THE CODE SUBJECT TO THE TERMS HEREOF. BY USING THE CODE, YOU
# AGREE TO THESE TERMS. YOUR USE OF THE CODE IS AT YOUR OWN RISK. SAS INSTITUTE INC. MAKES NO REPRESENTATION
# OR WARRANTY, EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, WARRANTIES OF MERCHANTABILITY, FITNESS FOR
# A PARTICULAR PURPOSE, NONINFRINGEMENT AND TITLE, WITH RESPECT TO THE CODE.
#
# The Code is intended to be used solely as part of a product ("Software") you currently have licensed from
# SAS Institute Inc. or one of its subsidiaries or authorized agents ("SAS"). The Code is designed to either
# correct an error in the Software or to add functionality to the Software, but has not necessarily been tested.
# Accordingly, SAS makes no representation or warranty that the Code will operate error-free. SAS is under no
# obligation to maintain or support the Code.
#
# Neither SAS nor its licensors shall be liable to you or any third party for any general, special, direct,
# indirect, consequential, incidental or other damages whatsoever arising out of or related to your use or
# inability to use the Code, even if SAS has been advised of the possibility of such damages.
#
# Except as otherwise provided above, the Code is governed by the same agreement that governs the Software.
# If you do not have an existing agreement with SAS governing the Software, you may not use the Code.



# Function to display the main menu
show_main_menu() {
    clear
    echo -e "\e[1;36mSAS 9.4 Released Main Menu\e[0m"
    echo -e "\e[1;33mPlease select from below options.\e[0m"
    echo -e "\e[1;32m1. Troubleshoot issue related to SAS Visual Analytics\e[0m"
    echo -e "\e[1;32m2. Troubleshoot issue related to SAS Web Report Studio\e[0m"
    echo -e "\e[1;32m3. Exit\e[0m"
}

# Function to handle main menu input
handle_main_menu_input() {
    local choice
    read -p "Enter choice [ 1 - 3 ]: " choice
    case $choice in
        1)
            echo -e "\e[1;34mYou selected SAS 9.4 - Collect logs for issue related to SAS Visual Analytics\e[0m"
            sleep 2
            copy_logs_from_VA
            ;;
        2)
            echo -e "\e[1;34mYou selected SAS 9.4 - Collect logs for issue related to SAS Web Report Studio\e[0m"
            sleep 2
            copy_logs_from_WRS
            ;;
        3)
            exit 0
            ;;
        *)
            echo -e "\e[1;31mInvalid choice...\n\e[0m"
            sleep 1
            ;;
    esac
}


# Function to copy VA logs from the current server
copy_logs_from_VA() {
    DATE=$(date +"%Y-%m-%d-%H-%M")
    echo "Today's date is $DATE"
    SASCONFIGDIR=$(locate -n 1 SASAdmin9.4.log | sed 's/\/Web.*//')
    SASWEBAPP=$(locate SASVisualAnalyticsViewer | grep -i '/Web/Logs/' -m 1 | awk -F'/' '{for(i=1; i<=NF; i++) if ($i ~ /SASServer[1-9]_1|SASServer1[0-5]_1/) print $i}')
    echo "Copying VA logs from the current server..."
    read -p $'\e[1;36mEnter your SAS Case Number:\e[0m ' csmcase
    echo
    mkdir -p /tmp/$csmcase
    cp "$SASCONFIGDIR/Web/Logs/$SASWEBAPP/"* "/tmp/$csmcase"
    cp "$SASCONFIGDIR/Web/WebAppServer/$SASWEBAPP/logs/server.log" "$SASCONFIGDIR/Web/WebAppServer/$SASWEBAPP/logs/catalina.out" "/tmp/$csmcase"
tar cvfz /tmp/$csmcase.tar.gz -C /tmp $csmcase
    echo "Logs have been copied and tar file is created in /tmp/$csmcase"
    echo "You can share us the /tmp/$csmcase.tar.gz file over the Service now case or upload the same in SAS TSDrive"
        sleep 5

  read -p $'\e[1;36mWould to like to go to Main Menu (Y/N): \e[0m' menu


if [ "$menu" == "Y" ]; then
    show_main_menu
else
    exit
fi
}

# Function to copy WRS logs from the current server
copy_logs_from_WRS() {
    DATE=$(date +"%Y-%m-%d-%H-%M")
    echo "Today's date is $DATE"
    SASCONFIGDIR=$(locate -n 1 SASAdmin9.4.log | sed 's/\/Web.*//')
    SASWEBREPORT=$(locate SASWebReport | grep -i '/Web/Logs/SASServer' -m 1 | sed 's|\(.*SASServer[0-9]*_[0-9]*\).*|\1|')
    SASWEBAPP=$(locate SASWebReport | grep -i '/Web/Logs/' -m 1 | sed -n 's|.*\(SASServer[12]_1\).*|\1|p')
    echo "Copying logs from the current server..."
    read -p $'\e[1;36mEnter your SAS Case Number:\e[0m ' csmcase
    echo
    mkdir -p /tmp/$csmcase
    cp "$SASWEBREPORT/SASWebReport"* "/tmp/$csmcase"
    cp "$SASCONFIGDIR/Web/WebAppServer/$SASWEBAPP/logs/server.log" "$SASCONFIGDIR/Web/WebAppServer/$SASWEBAPP/logs/catalina.out" "/tmp/$csmcase"
tar cvfz /tmp/$csmcase.tar.gz -C /tmp $csmcase
    echo "Logs have been copied and tar file is created in /tmp/$csmcase"
    echo "You can share us the /tmp/$csmcase.tar.gz file over the Service now case or upload the same in SAS TSDrive"
sleep 5

  read -p $'\e[1;36mWould to like to go to Main Menu (Y/N): \e[0m' menu


if [ "$menu" == "Y" ]; then
    show_main_menu
else
    exit
fi

}

# Main program loop
while true; do
    show_main_menu
    handle_main_menu_input
done
