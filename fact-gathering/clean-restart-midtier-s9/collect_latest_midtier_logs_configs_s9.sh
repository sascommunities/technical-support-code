#!/bin/bash
# This script collects latest midtier logs only and configuration files for Application Servers, Web Servers, and
# Cache Locator, Active MQ and WIPS services.
# It creates a "log bundle" zip file that is stored in /tmp directory.
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
#Make sure to have at least 5GB free space in /tmp directory

# Usage:
#1. chmod 755 collect_midtier_logs_configs_s9.sh
#2. ./collect_latest_midtier_logs_configs_s9.sh

####Checking available disk space in /tmp directory#######
###################################################################
usage() {
  echo ""
  echo " Each parameter is required to be set. "
  echo " ./collect_latest_midtier_logs_configs_s9.sh -t <all|latest> -d <SAS-configuration-directory/Levn>"
  echo " -t | Collect "all" OR "latest" logs only - all/latest"
  echo " -d | SAS Configuration directory, for example: /opt/sas/config/Lev1/"
  echo " -w | Script's work directory, for example: /tmp/ IMPORTANT: The OS user must have read and write privileges to that directory"
  echo ""
  exit
}

function initial_setup() {
  SCRIPTLOG=$TEMPLOGSDIR/scriptLogFile.log
  if [ -d "$SASCONFIGDIR" ]; then
    echo "$SASCONFIGDIR exists..."
  else
    echo "$SASCONFIGDIR does not exists..."
    echo "Exiting..."
    exit 1
  fi
}

########### CHECK IF SASCONFIG EXISTS ########
function check_config_dir() {
  SCRIPTLOG=$TEMPLOGSDIR/scriptLogFile.log
  if [ -d "$SASCONFIGDIR" ]; then
    echo "$SASCONFIGDIR exists..."
  else
    echo "$SASCONFIGDIR does not exists..."
    echo "Exiting..."
    exit 1
  fi
}
###################################################################
function checking_free_space_latest() {
  if [ $(df -m /$TEMPLOGSDIRSHORT | awk 'NR==2{print$4}') -lt 1000 ]; then
    echo "ERROR: There is not enough free space in the $TEMPLOGSDIRSHORT directory to continue."
    echo "Please clean up the directory to have at least 1GB of free space."
    exit 1
  fi
}

function checking_free_space_all() {
  if [ $(df -m /$TEMPLOGSDIRSHORT | awk 'NR==2{print$4}') -lt 5000 ]; then
    echo "ERROR: There is not enough free space in the $TEMPLOGSDIRSHORT directory to continue."
    echo "Please clean up the directory to have at least 5GB of free space."
    exit 1
  fi
}

####Checking /tmp permissions#######
function tmp_permissions() {
  mkdir -p /$TEMPLOGSDIRSHORT >/dev/null 2>&1
  if [ ! -w "/$TEMPLOGSDIRSHORT" ]; then
    echo "ERROR: The user doesn't have writable permission to the $TEMPLOGSDIRSHORT directory."
    echo "Please try with another user or change script's work directory."
    exit 1
  fi
}

function checking_if_zip_exists() {
  if [ -f /$TEMPLOGSDIR/$LOGBUNDLEFILE ]; then
    sleep 45
  fi
}

DATE=$(date +"%Y-%m-%d-%H-%M")
#SASCONFIGDIR="$(locate -n 1 SASAdmin9.4.log | sed 's/\/Web.*//')"

LOGBUNDLEFILE=log-bundle-$DATE.zip
#TEMPLOGSDIR="/tmp/LogsAndConfigs-$DATE"
#SCRIPTLOG=$TEMPLOGSDIR/scriptLogFile.log

###### SAS Web App and Web servers logs and configuration files ##############
function collect_web_app_srv_logs() {
  for dir in $(seq -f "%g_1" 16); do

    if [ -d "$SASCONFIGDIR/Web/WebAppServer/SASServer$dir/" ]; then
      echo "INFO: Creating directories for "SASServer$dir" logs and config files"
      mkdir $TEMPLOGSDIR/SASServer$dir-ServerLogs >>$SCRIPTLOG 2>&1
      mkdir $TEMPLOGSDIR/SASServer$dir-AppLogs >>$SCRIPTLOG 2>&1
      mkdir $TEMPLOGSDIR/SASServer$dir-config >>$SCRIPTLOG 2>&1
      echo "INFO: Copying SASServer$dir Server logs"

      cp -R $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs/{server.log,catalina.out,gemfire.log} $TEMPLOGSDIR/SASServer$dir-ServerLogs/ >>$SCRIPTLOG 2>&1

      echo "INFO: Copying SASServer$dir Web Appliation logs"
      cp -R $SASCONFIGDIR/Web/Logs/SASServer$dir/*.log $TEMPLOGSDIR/SASServer$dir-AppLogs/ >>$SCRIPTLOG 2>&1

      echo "INFO: Copying configuration files"
      cp -R $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/conf/{server.xml,jaas.config,catalina.properties,web.xml} $TEMPLOGSDIR/SASServer$dir-config/ >>$SCRIPTLOG 2>&1
      cp -R $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/bin/setenv.sh $TEMPLOGSDIR/SASServer$dir-config/ >>$SCRIPTLOG 2>&1

    else

      echo "INFO: "SASServer$dir" not found. Skipping..."
    fi
  done
}

function collect_web_app_srv_logs_all() {
  for dir in $(seq -f "%g_1" 16); do

    if [ -d "$SASCONFIGDIR/Web/WebAppServer/SASServer$dir/" ]; then
      echo "INFO: Creating directories for "SASServer$dir" logs and config files"
      mkdir $TEMPLOGSDIR/SASServer$dir-ServerLogs >>$SCRIPTLOG 2>&1
      mkdir $TEMPLOGSDIR/SASServer$dir-AppLogs >>$SCRIPTLOG 2>&1
      mkdir $TEMPLOGSDIR/SASServer$dir-config >>$SCRIPTLOG 2>&1
      echo "INFO: Copying SASServer$dir Server logs"

      cp -R $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs/* $TEMPLOGSDIR/SASServer$dir-ServerLogs/ >>$SCRIPTLOG 2>&1

      #ALL SAS Web Application Logs#
      echo "INFO: Copying SASServer$dir Web Appliation logs"
      cp -R $SASCONFIGDIR/Web/Logs/SASServer$dir/* $TEMPLOGSDIR/SASServer$dir-AppLogs/ >>$SCRIPTLOG 2>&1

      #SAS WebAppServer configuration files#
      echo "INFO: Copying configuration files"
      cp -R $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/conf/{server.xml,jaas.config,catalina.properties,web.xml} $TEMPLOGSDIR/SASServer$dir-config/ >>$SCRIPTLOG 2>&1
      cp -R $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/bin/setenv.sh $TEMPLOGSDIR/SASServer$dir-config/ >>$SCRIPTLOG 2>&1

    else

      echo "INFO: "SASServer$dir" not found. Skipping..."
    fi
  done
}

function collect_web_srv_logs() {
  echo "INFO: Copying SAS Web Server Logs"
  mkdir $TEMPLOGSDIR/WebServer/ >>$SCRIPTLOG 2>&1
  cp -R $SASCONFIGDIR/Web/WebServer/logs/{access*.log,error*.log,ssl_request*.log} $TEMPLOGSDIR/WebServer/ >>$SCRIPTLOG 2>&1
}

function collect_web_srv_logs_all() {
  echo "INFO: Copying SAS Web Server Logs"
  mkdir $TEMPLOGSDIR/WebServer/ >>$SCRIPTLOG 2>&1
  cp -R $SASCONFIGDIR/Web/WebServer/logs/* $TEMPLOGSDIR/WebServer/ >>$SCRIPTLOG 2>&1
}

#SAS Web Server configuration files
function collect_web_srv_configs() {
  cp -R $SASCONFIGDIR/Web/WebServer/conf/{httpd.conf,sas.conf} $TEMPLOGSDIR/WebServer/ >>$SCRIPTLOG 2>&1
  cp -R $SASCONFIGDIR/Web/WebServer/conf/extra/httpd-ssl.conf $TEMPLOGSDIR/WebServer/ >>$SCRIPTLOG 2>&1
}

###### Active MQ ##############

function collect_activemq_logs() {
  echo "INFO: Copying Active MQ Logs"

  mkdir $TEMPLOGSDIR/activemq/ >>$SCRIPTLOG 2>&1
  cp -R $SASCONFIGDIR/Web/activemq/data/activemq.log $TEMPLOGSDIR/activemq/ >>$SCRIPTLOG 2>&1
}

function collect_activemq_logs_all() {
  echo "INFO: Copying Active MQ Logs"

  mkdir $TEMPLOGSDIR/activemq/ >>$SCRIPTLOG 2>&1
  cp -R $SASCONFIGDIR/Web/activemq/data/*.log* $TEMPLOGSDIR/activemq/ >>$SCRIPTLOG 2>&1
}

function collect_activemq_configs() {
  echo "INFO: Copying Active MQ configuration file"
  cp -R $SASCONFIGDIR/Web/activemq/conf/activemq.xml $TEMPLOGSDIR/activemq/ >>$SCRIPTLOG 2>&1
}

###### Cache Locator###########
function collect_gemfire_logs() {
  # 2025-12-05 gw Need to handle instances other than ins_41415.

  shopt -s nullglob
  clpaths=( "$SASCONFIGDIR"/Web/*/instances/ins_* )
  shopt -u nullglob

  # The clpaths array will contain all the cache locator instance paths.

  # Write a message if we found none.
  if [ ${#clpaths[@]} -eq 0 ]; then
    echo "Cache Locator not found. Skipping."
    return
  fi

  # Now we can loop through them.
  for instance_path in "${clpaths[@]}"; do
    instance_name=$(basename "$instance_path")
    echo "INFO: Copying Cache Locator Logs for instance $instance_name"
    mkdir -p "$TEMPLOGSDIR/cachelocator/$instance_name/" >>$SCRIPTLOG 2>&1
    cp -R "$instance_path/gemfire.log" "$TEMPLOGSDIR/cachelocator/$instance_name/" >>$SCRIPTLOG 2>&1
  done
}

function collect_gemfire_logs_all() {
  # 2025-12-05 gw Need to handle instances other than ins_41415.

  shopt -s nullglob
  clpaths=( "$SASCONFIGDIR"/Web/*/instances/ins_* )
  shopt -u nullglob

  # The clpaths array will contain all the cache locator instance paths.

  # Write a message if we found none.
  if [ ${#clpaths[@]} -eq 0 ]; then
    echo "Cache Locator not found. Skipping."
    return
  fi

  # Now we can loop through them.
  for instance_path in "${clpaths[@]}"; do
    instance_name=$(basename "$instance_path")
    echo "INFO: Copying Cache Locator Logs for instance $instance_name"
    mkdir -p "$TEMPLOGSDIR/cachelocator/$instance_name/" >>$SCRIPTLOG 2>&1
    cp -R "$instance_path/"*.log "$TEMPLOGSDIR/cachelocator/$instance_name/" >>$SCRIPTLOG 2>&1
  done
}

###### Web Infrastructure Platform Data Server ###########
function collect_wipds_configs() {
  mkdir $TEMPLOGSDIR/wipds/ >>$SCRIPTLOG 2>&1
  echo "INFO: Copying Web Infrastructure Platform Data Server configuration file"
  cp -R $SASCONFIGDIR/WebInfrastructurePlatformDataServer/data/postgresql.conf $TEMPLOGSDIR/wipds/ >>$SCRIPTLOG 2>&1
}

###### Creating log bundle ###########
function create_log_bundle() {
  echo "INFO: Creating log bundle..."

  zip -qrm /$TEMPLOGSDIR/$LOGBUNDLEFILE /$TEMPLOGSDIR >>$SCRIPTLOG 2>&1
  if [ -f /$TEMPLOGSDIR/$LOGBUNDLEFILE ]; then
    echo "INFO: Log bundle file has been created successfully"
    echo "INFO: Operation finished successfully. Please copy $TEMPLOGSDIR/$LOGBUNDLEFILE file to your local drive and then upload it to the track"
  else
    echo "ERROR: Log bundle file has NOT been created successfully. Contact SAS Technical Support for assistance"
  fi
}

## Program Start####
#shopt -s nocasematch
if [[ $1 == "" ]]; then
  usage
else
  while getopts :t:d:w: opt; do
    case $opt in
    t)
      TIME="$OPTARG"
      if [ "$TIME" = "all" ]; then
        COLLECT_ALL="true"
      elif [ "$TIME" = "latest" ]; then
        COLLECT_ALL="false"
      else
        usage
        exit 1
      fi
      ;;
    d)
      SASCONFIGDIR="$OPTARG"
      if [ -d "$SASCONFIGDIR" ]; then
        echo " Working on $SASCONFIGDIR "
      else
        usage
        exit 1
      fi
      ;;
    w)
      TEMPLOGSDIR="$OPTARG/LogsAndConfigs-$DATE"
      TEMPLOGSDIRSHORT="$OPTARG"
      tmp_permissions
      mkdir -p $TEMPLOGSDIR
      if [ -d "$TEMPLOGSDIR" ]; then
        echo " Working on $TEMPLOGSDIR "
      else
        usage
        exit 1
      fi
      ;;
    *) usage ;;
    esac
  done
fi

#SASCONFIGDIR="$(locate -n 1 SASAdmin9.4.log | sed 's/\/Lev.*//')"/$CONFIG_LEVEL
#echo "SAS config directory:  $SASCONFIGDIR"

if [ "$COLLECT_ALL" = 'true' ]; then

  check_config_dir
  checking_free_space_all
  tmp_permissions
  checking_if_zip_exists
  collect_web_app_srv_logs_all
  collect_web_srv_logs_all
  collect_web_srv_configs
  collect_activemq_logs_all
  collect_activemq_configs
  collect_gemfire_logs_all
  collect_wipds_configs
  create_log_bundle

else
  check_config_dir
  checking_free_space_latest
  tmp_permissions
  checking_if_zip_exists
  collect_web_app_srv_logs
  collect_web_srv_logs
  collect_web_srv_configs
  collect_activemq_logs
  collect_activemq_configs
  collect_gemfire_logs
  collect_wipds_configs
  create_log_bundle

fi

exit 0
