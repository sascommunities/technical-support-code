#!/bin/bash
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
# Usage: 1. chmod 755 clean_midtier_s9.sh 2. ./clean_midtier_s9.sh
############# STOP Mid Tier Services #########
# At this time STOP servers manually.
#cd $SASCONFIGDIR
#./sas.servers.mid stop

#Initialize Variables
DATE=$(date +"%Y-%m-%d-%H-%M")
CACHELOCATOR_ONLY=false
CONFIG_LEVEL="Lev1"

usage() {
  echo ""
  echo " Each parameter is required to be set. "
  echo " ./clean_midtier_s9.sh -c <true|false> -d <SAS-configuration-directory/Levn> "
  echo " -c | Clean cache locator only - true/false"
  echo " -d | SAS-configuration-directory/Levn"
  echo ""
  exit
}

# Create functons

########### CHECK IF SASCONFIG EXISTS ########
function check_config_dir() {
  if [ -d "$SASCONFIGDIR" ]; then
    echo "$SASCONFIGDIR exists..."
  else
    echo "$SASCONFIGDIR does not exists..."
    echo "Exiting..."
    exit 1
  fi
}
##############WEB APP SERVER##################
function clean_web_app_server() {
  for dir in $(seq -f "%g_1" 16); do

    if [ -d "$SASCONFIGDIR/Web/WebAppServer/SASServer$dir/" ]; then
      echo "$SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs"
      mkdir $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs/ServerBackup-$DATE >/dev/null 2>&1
      ## CHECK IF DIR EXISTS####
      if [ -d "$SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs/ServerBackup-$DATE" ]; then
        echo "Backing up now ..."
        mv $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs/{*.log,*.log*,*.txt,*.out} \
          $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs/ServerBackup-$DATE >/dev/null 2>&1

        echo "Cleaning work and temp dirs ..."
        rm -rf $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/temp/*
        rm -rf $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/work/*
        echo "Cleaning work and temp dirs ..."
        touch $SASCONFIGDIR/Web/WebAppServer/SASServer$dir/logs/server.log

      else
        echo ""$ServerBackup-$DATE" not found. Skipping..."
      fi
    fi
  done
}

############# GEMFIRE ########################
function clean_gemfire() {
  #2025-12-05 gw Add support for multiple instances
  shopt -s nullglob
  clpaths=( "$SASCONFIGDIR/Web/*/instances/ins_*" )
  shopt -u nullglob

  if [ ${#clpaths[@]} -gt 0 ]; then
    for GEMDIR in "${clpaths[@]}"; do
      echo "Working on GEMFIRE/GEODE $GEMDIR - Cleaning..."
      rm -f $GEMDIR/{*.log,*.dat,.locator} >/dev/null 2>&1
      rm -f $GEMDIR/ConfigDiskDir*/* >/dev/null 2>&1
    done
  else
    echo "Cache locator not found. Skipping."
  fi
}
############# ACTIVEMQ #######################
function clean_activemq() {
  ACTIVEMQ="$SASCONFIGDIR/Web/activemq"

  if [ -d $ACTIVEMQ ]; then

    echo "Working on ACTIVEMQ  $ACTIVEMQ/data - Cleaning..."
    rm -rf $ACTIVEMQ/data/* >/dev/null 2>&1
  else
    echo "${ACTIVEMQ} not found. Skipping."
  fi
}

################  WEB SERVER #################
function clean_web_Logs_dir() {
  for dir in $(seq -f "%g_1" 16); do

    if [ -d "$SASCONFIGDIR/Web/Logs/SASServer$dir/" ]; then
      echo "$SASCONFIGDIR/Web/Logs/SASServer$dir"
      mkdir $SASCONFIGDIR/Web/Logs/SASServer$dir/ServerBackup-$DATE >/dev/null 2>&1

      ## CHECK IF DIR EXISTS####
      if [ -d "$SASCONFIGDIR/Web/Logs/SASServer$dir/ServerBackup-$DATE" ]; then
        echo "Backing up Web/Logs now ..."
        mv $SASCONFIGDIR/Web/Logs/SASServer$dir/*log* \
          $SASCONFIGDIR/Web/Logs/SASServer$dir/ServerBackup-$DATE >/dev/null 2>&1
      else
        echo ""$SASCONFIGDIR/Web/Logs/SASServer$dir/$ServerBackup-$DATE" not found. Skipping..."
      fi
    fi
  done
}

######## LAST  Web/WebServer/logs ############
function clean_web_logs_dir() {
  mkdir $SASCONFIGDIR/Web/WebServer/logs/Backup-$DATE >/dev/null 2>&1
  #echo "$SASCONFIGDIR/Web/WebServer/logs/Backup-$DATE"
  if [ -d "$SASCONFIGDIR/Web/WebServer/logs/Backup-$DATE" ]; then
    echo "Backing up Web/WebServer/logs now ..."
    mv $SASCONFIGDIR/Web/WebServer/logs/*.log \
      $SASCONFIGDIR/Web/WebServer/logs/Backup-$DATE >/dev/null 2>&1
  else
    echo ""$SASCONFIGDIR/Web/WebServer/logs/$Backup-$DATE" not found. Skipping..."
  fi
}
## Program Start####
if [[ $1 == "" ]]; then
  usage
else
  while getopts :c:d: opt; do
    case $opt in
    c)
      CACHEL="$OPTARG"
      if [ "$CACHEL" = "true" ]; then
        CACHELOCATOR_ONLY="true"
      elif [ "$CACHEL" = "false" ]; then
        CACHELOCATOR_ONLY="false"
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

    *) usage ;;
    esac
  done
fi

echo "cachelocator only is : $CACHELOCATOR_ONLY"

#  Locate SASCONFIG DIR.
#
echo "SAS config directory selected is : $SASCONFIGDIR"

if [ -d "$SASCONFIGDIR" ]; then
  echo " Working on $SASCONFIGDIR "
else
  echo " $SASCONFIGDIR does not exit - aborting... "

fi

if [ "$CACHELOCATOR_ONLY" = 'true' ]; then
  echo "Cleaning Cache locator only..."
  check_config_dir
  clean_gemfire
else
  echo "Cleaning midtier ..."
  check_config_dir
  clean_web_app_server
  clean_gemfire
  clean_activemq
  clean_web_Logs_dir
  clean_web_logs_dir
fi

echo "Script finished cleaning..."
exit 0

## START Mid Tier Services  after checking dangling pids##
#cd $SASCONFIGDIR
# ps -ef | grep -i sas
# ps -ef | grep -i java
# kill -9 <pids>
#### START SAS Servers
#./sas.servers.mid start
#####################END #####################
