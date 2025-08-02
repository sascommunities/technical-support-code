#!/bin/bash
# This script captures information from Kubernetes cluster with a Viya 4 deployment.
# Date: 04MAY2023
#
# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
version='get-k8s-info v1.5.10'

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

# Initialize log file
touch $(pwd)/get-k8s-info.log > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    touch /tmp/get-k8s-info.log > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Unable to create log file in '$(pwd)' or '/tmp'."
        cleanUp 0
    else
        logfile=/tmp/get-k8s-info.log
    fi
else
    logfile="$(pwd)/get-k8s-info.log"
fi
echo -e "$version\n$(date)\n$(bash --version | head -1)\n$(uname -a)\nCommand: ${0} ${@}\n" > $logfile

script=$(echo $0 | rev | cut -d '/' -f1 | rev)
function usage {
    echo Version: "$version"
    echo; echo "Usage: $script [OPTIONS]..."
    echo;
    echo "Capture information from a Viya 4 deployment."
    echo;
    echo "  -c|--case        (Optional) SAS Tech Support case number"
    echo "  -n|--namespaces  (Optional) Comma separated list of namespaces"
    echo "  -p|--deploypath  (Optional) Path of the viya \$deploy directory"
    echo "  -i|--tfvars      (Optional) Path of the terraform.tfvars file"
    echo "  -a|--ansiblevars (Optional) Path of the ansible-vars.yaml file"
    echo "  -o|--out         (Optional) Path where the .tgz file will be created"
    echo "  -d|--disabletags (Optional) Disable specific debug tags. By default, all tags are enabled."
    echo "                              Available values are: 'backups', 'config', 'opensearch', 'performance, 'postgres' and 'rabbitmq'"
    echo "  -s|--sastsdrive  (Optional) Send the .tgz file to SASTSDrive through sftp."
    echo "                              Only use this option after you were authorized by Tech Support to send files to SASTSDrive for the case."
    echo "  -w|--workers     (Optional) Number of simultaneous "kubectl" commands that the script can execute in parallel."
    echo "                              If not specified, 5 workers are used by default."
    echo "  -u|--no-update   (Optional) Disable automatic update checks."
    echo;
    echo "Examples:"
    echo;
    echo "Run the script with no arguments for options to be prompted interactively"
    echo "  $ $script"
    echo;
    echo "You can also specify options in the command line"
    echo "  $ $script --case CS0001234 --namespace viya-prod --deploypath /home/user/viyadeployment --out /tmp"
    echo;
    echo "                                 By: Alexandre Gomes - Jun 10, 2024"
    echo "https://gitlab.sas.com/sbralg/tools-and-scripts/-/blob/main/get-k8s-info"
}
function version {
    echo "$version"
}

if type timeout > /dev/null 2>> $logfile; then
    timeoutCmd='timeout'
else
    echo "DEBUG: 'timeout' command not available. Using custom timeout function" > $logfile
    timeoutCmd='gkiTimeout'

    function gkiTimeout {
        seconds=$1
        shift
        taskCmd=("$@")
        (
            "${taskCmd[@]}" &
            taskPid=$!
            trap -- '' SIGTERM
            (
                sleep $seconds
                kill -9 $taskPid 2> /dev/null
            ) &
            timeoutPid=$!
            wait $taskPid
            taskRc=$?
            if [[ $taskRc -eq 137 ]]; then taskRc=124; fi
            sleepPid=$(ps -o pid= --ppid $timeoutPid 2> /dev/null)
            kill -9 $sleepPid $timeoutPid 2> /dev/null
            return $taskRc
        )
    }
fi

# Handle ctrl+c
trap cleanUp SIGINT
function cleanUp() {
    tput cnorm
    tput smam
    if [ -f $logfile ]; then 
        if [[ $1 -eq 1 || -z $1 ]]; then 
            if [[ -z $1 ]]; then echo -e "\nFATAL: The script was terminated unexpectedly." | tee -a $logfile; fi
            echo -e "\nScript log saved at: $logfile"
        else rm -f $logfile; fi
    fi
    # Kill Subshells
    if [[ -d $TEMPDIR/.get-k8s-info ]]; then
        # Kill Workers
        for worker in $(seq 1 $workers); do
            if [[ -f $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid ]]; then
                workerPid=$(cat $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid)
                jobs=$(ps -o pid= --ppid $workerPid 2> /dev/null)
                kill $jobs > /dev/null 2>&1
                kill $workerPid > /dev/null 2>&1
            fi
        done
        # Kill Task Manager
        if [[ -f $TEMPDIR/.get-k8s-info/taskmanager/pid ]]; then
            taskManagerPid=$(cat $TEMPDIR/.get-k8s-info/taskmanager/pid)
            kill $taskManagerPid > /dev/null 2>&1
        fi
    fi
    rm -rf $TEMPDIR $updatedScript $k8sApiResources
    exit $1
}

# Initialize Variables
UPDATE=true
OPENSEARCH=true
PERFORMANCE=true
POSTGRES=true
RABBITMQ=true
CONFIG=true
BACKUPS=true
SASTSDRIVE=false
WORKERS=5

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help|--usage)
      usage
      cleanUp 0
      ;;
    -v|--version)
      version
      cleanUp 0
      ;;
    -w|--workers)
      WORKERS="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--case|-t|--track)
      CASENUMBER="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--namespace|--namespaces)
      USER_NS="$2"
      # Validate the user provided namespace
      for ns in $(tr ',' ' ' <<< $USER_NS); do
        if ! echo $ns | grep -E '^[a-z0-9][-a-z0-9]*[a-z0-9]$' > /dev/null; then
            echo;echo "ERROR: Namespace '$ns' is invalid.";echo
            cleanUp 1
        fi
      done
      shift # past argument
      shift # past value
      ;;
    --debugtag|--debugtags)
      echo -e "WARNING: The '--debugtag' option is deprecated. All debug tags are already enabled by default.\n" | tee -a $logfile
      shift # past argument
      shift # past value
      ;;
    -d|--disabletag|--disabletags)
      TAGS=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      if [[ $TAGS =~ 'postgres' ]]; then POSTGRES=false;fi
      if [[ $TAGS =~ 'rabbitmq' ]]; then RABBITMQ=false;fi
      if [[ $TAGS =~ 'config' || $TAGS =~ 'consul' ]]; then CONFIG=false;fi
      if [[ $TAGS =~ 'backup' ]]; then BACKUPS=false;fi
      if [[ $TAGS =~ 'performance' ]]; then PERFORMANCE=false;fi
      if [[ $TAGS =~ 'opensearch' ]]; then OPENSEARCH=false;fi
      shift # past argument
      shift # past value
      ;;
    -l|--log|--logs)
      echo -e "\nINFO: The '-l|--log|--logs' option is deprecated. All logs from all pods are collected by default." | tee -a $logfile
      shift # past argument
      shift # past value
      ;;
    -p|--deploypath)
      DEPLOYPATH="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--out)
      OUTPATH="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--tfvars)
      TFVARSFILE="$2"
      shift # past argument
      shift # past value
      ;;
    -a|--ansiblevars)
      ANSIBLEVARSFILE="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--sastsdrive)
      $timeoutCmd 5 bash -c 'cat < /dev/null > /dev/tcp/sft.sas.com/22' > /dev/null 2>> $logfile
      if [ $? -ne 0 ]; then
          echo -e "WARNING: Connection to SASTSDrive not available. The script won't try to send the .tgz file to SASTSDrive.\n" | tee -a $logfile
      else SASTSDRIVE="true"; fi
      shift # past argument
      ;;
    -u|--no-update)
      UPDATE='false'
      shift # past argument
      ;;
    -*|--*)
      usage
      echo -e "\nERROR: Unknown option $1" | tee -a $logfile
      cleanUp 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [[ $UPDATE == 'true' ]]; then
    # Check for updates
    latestVersion=$(curl -s https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/get-k8s-info-vk/get-k8s-info.sh 2>> $logfile | grep '^version=' | cut -d "'" -f2)
    if [[ ! -z $latestVersion ]]; then
        if [[ $(cut -d 'v' -f2 <<< $latestVersion | tr -d '.') -gt $(version | cut -d 'v' -f2 | tr -d '.') ]]; then
            echo -e "\nWARNING: A new version is available! ($latestVersion). It is highly recommended to use the latest version." | tee -a $logfile
            scriptPath=$(dirname $(realpath -s $0))
            if [[ -w ${scriptPath}/${script} ]]; then
                echo;
                read -p "Do you want to update this script ($(version))? (y/n) " k
                echo "DEBUG: Wants to update? $k" >> $logfile
                if [ "$k" == 'y' ] || [ "$k" == 'Y' ] ; then
                    updatedScript=$(mktemp)
                    curl -s -o $updatedScript https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/get-k8s-info-vk/get-k8s-info.sh >> $logfile 2>&1
                    if [[ $? -eq 0 ]]; then
                        scriptPath=$(dirname $(realpath -s $0))
                        if cp $updatedScript $scriptPath/$script > /dev/null 2>> $logfile; then echo -e "INFO: Script updated successfully. Restarting...\n";rm -f $updatedScript;$scriptPath/$script ${@};exit $?;else echo -e "ERROR: Script update failed!\n\nINFO: Update it manually from https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/get-k8s-info-vk" | tee -a $logfile;cleanUp 1;fi
                    else
                        echo -e "ERROR: Error while downloading the script!\n\nINFO: Update it manually from https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/get-k8s-info-vk" | tee -a $logfile
                        cleanUp 1
                    fi
                else
                    echo;
                fi
            else
                echo -e "WARNING: The current user doesn't have write permission to modify the script file '$scriptPath/$script'." | tee -a $logfile
                echo -e "\nINFO: Update the script manually from:\n  https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/get-k8s-info-vk \n" | tee -a $logfile
                read -p "Would you like to proceed with the outdated version of the script ($(version)) this time? (y/n) " k
                echo "DEBUG: Wants to continue outdated? $k" >> $logfile
                if [ "$k" != 'y' ] && [ "$k" != 'Y' ] ; then
                    cleanUp 1
                else
                    echo;
                fi
            fi
        fi
    fi
else
    echo "INFO: This script will not check for updates. Please verify that you're using the latest available version from:" | tee -a $logfile
    echo -e "\n  https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/get-k8s-info-vk \n" | tee -a $logfile
fi

# Check kubectl
if type kubectl > /dev/null 2>&1 && type oc > /dev/null 2>&1; then
    # Both clients are installed. Check if k8s is OpenShift.
    if oc version -o yaml 2>> $logfile | grep openshift > /dev/null; then
        KUBECTLCMD='oc'
    else
        KUBECTLCMD='kubectl'
    fi
elif type kubectl > /dev/null 2>> $logfile; then
    KUBECTLCMD='kubectl'
elif type oc > /dev/null 2>> $logfile; then
    KUBECTLCMD='oc'
else
    echo;echo "ERROR: Neither 'kubectl' or 'oc' are installed in PATH." | tee -a $logfile
    cleanUp 1
fi
k8sApiResources=$(mktemp)
if ! $KUBECTLCMD api-resources > $k8sApiResources 2>> $logfile; then
    $KUBECTLCMD api-resources > /dev/null
    echo -e "\nERROR: Error while executing '$KUBECTLCMD' commands. Make sure you're able to use '$KUBECTLCMD' against the kubernetes cluster before running this script." | tee -a $logfile
    cleanUp 1
fi

# Check if k8s is OpenShift
if grep project.openshift.io $k8sApiResources > /dev/null; then isOpenShift='true'
else isOpenShift='false';fi
echo "DEBUG: Is OpenShift? $isOpenShift" >> $logfile

# Check CASENUMBER
if [ -z $CASENUMBER ]; then 
    if [ $SASTSDRIVE == 'true' ]; then
        read -p " -> SAS Tech Support case number (required): " CASENUMBER
    else
        read -p " -> SAS Tech Support case number (leave blank if not known): " CASENUMBER
        if [ -z $CASENUMBER ]; then CASENUMBER=CS0000000; fi
    fi
fi
echo CASENUMBER: $CASENUMBER >> $logfile
if ! grep -E '^CS[0-9]{7}$' > /dev/null 2>> $logfile <<< $CASENUMBER; then
    echo "ERROR: Invalid case number. Expected format: CS1234567" | tee -a $logfile
    cleanUp 1
fi

# Check DEPLOYPATH
if [ -z $DEPLOYPATH ]; then 
    read -p " -> Specify the path of the viya \$deploy directory ($(pwd)): " DEPLOYPATH
    DEPLOYPATH="${DEPLOYPATH/#\~/$HOME}"
    if [ -z $DEPLOYPATH ]; then DEPLOYPATH=$(pwd); fi
fi
if [ $DEPLOYPATH != 'unavailable' ]; then
    DEPLOYPATH=$(realpath $DEPLOYPATH 2> /dev/null)
    # Exit if deployment assets are not found
    if [[ ! -d $DEPLOYPATH/site-config || ! -f $DEPLOYPATH/kustomization.yaml ]]; then 
        echo ERROR: Deployment assets were not found inside the provided \$deploy path: $(echo -e "site-config/\nkustomization.yaml" | grep -E -v $(ls $DEPLOYPATH 2>> $logfile | grep "^site-config$\|^kustomization.yaml$" | tr '\n' '\|')^dummy$)  | tee -a $logfile
        echo -e "\nTo debug some issues, SAS Tech Support requires information collected from files within the \$deploy directory.\nIf you are unable to access the \$deploy directory at the moment, run the script again with '--deploypath unavailable'" | tee -a $logfile
        cleanUp 1
    fi
else
    echo "WARNING: --deploypath set as 'unavailable'. Please note that SAS Tech Support may still require and request information from the \$deploy directory" | tee -a $logfile
fi
echo DEPLOYPATH: $DEPLOYPATH >> $logfile

namespaces=('kube-system')
# Look for Viya namespaces
echo 'DEBUG: Looking for Viya namespaces' >> $logfile
viyans=($(echo $($KUBECTLCMD get cm --all-namespaces 2>> $logfile | grep sas-deployment-metadata | awk '{print $1}') $($KUBECTLCMD get sasdeployment --all-namespaces --no-headers 2>> $logfile | awk '{print $1}') | tr ' ' '\n' | sort | uniq ))
if [ ${#viyans[@]} -gt 0 ]; then echo -e "VIYA_NS: ${viyans[@]}" >> $logfile; fi
if [ -z $USER_NS ]; then 
    if [ ${#viyans[@]} -gt 0 ]; then
        nsCount=0
        if [ ${#viyans[@]} -gt 1 ]; then
            echo -e '\nNamespaces with a Viya deployment:\n' | tee -a $logfile
            for ns in "${viyans[@]}"; do 
                echo "[$nsCount] ${viyans[$nsCount]}" | tee -a $logfile
                nsCount=$[ $nsCount + 1 ]
            done
            echo;read -n 1 -p " -> Select the namespace where the information should be collected from: " nsCount;echo
            if [ ! ${viyans[$nsCount]} ]; then
                echo -e "\nERROR: Option '$nsCount' invalid." | tee -a $logfile
                cleanUp 1
            fi
        fi
        USER_NS=${viyans[$nsCount]}
        echo -e "USER_NS: $USER_NS" >> $logfile
        namespaces+=($USER_NS)
    else
        echo "WARNING: A namespace was not provided and no Viya deployment was found in any namespace of the current kubernetes cluster. Is the KUBECONFIG file correct?" | tee -a $logfile
        echo "WARNING: The script will continue collecting information from Viya related namespaces" | tee -a $logfile
    fi
else
    echo -e "USER_NS: $USER_NS" >> $logfile
    hasViya=false
    for ns in $(echo $USER_NS | tr ',' ' '); do
        if $KUBECTLCMD get ns > /dev/null 2>&1; then
            validateNsWith='namespace'
        elif [[ $isOpenShift == 'true' ]]; then
            if $KUBECTLCMD get project > /dev/null 2>&1; then
                validateNsWith='project'
            fi
        else
            validateNsWith='none'
            echo "WARNING: Unable to check if the provided namespaces exist or not." | tee -a $logfile
        fi
        if [[ $validateNsWith != 'none' ]]; then
            if [ ! $($KUBECTLCMD get $validateNsWith --no-headers | awk '{print $1}' | grep -E "^$ns$") ]; then
                echo -e "\nERROR: Namespace '$ns' doesn't exist" | tee -a $logfile
                cleanUp 1
            fi
        fi
        if [[ " ${viyans[*]} " =~ " ${ns} " ]]; then hasViya=true
        elif ( $KUBECTLCMD -n ${ns} get cm 2>> $logfile | grep sas-deployment-metadata > /dev/null ) || [[ $($KUBECTLCMD -n ${ns} get sasdeployment 2> /dev/null | wc -l) -gt 0 ]]; then 
            hasViya=true
            viyans+=($ns)
        fi
        if [[ ! " ${namespaces[*]} " =~ " ${ns} " ]]; then namespaces+=($ns); fi
    done
    if [ $hasViya == false ]; then
        echo "WARNING: No Viya deployments were found in any of the namespaces provided" | tee -a $logfile
        echo "WARNING: The script will continue capturing information from the namespaces provided and Viya related namespaces" | tee -a $logfile
    fi
fi

# Check if an IaC Github Project was used
if [ -z $TFVARSFILE ]; then 
    if $KUBECTLCMD -n kube-system get cm sas-iac-buildinfo > /dev/null 2>&1; then 
        read -p " -> A viya4-iac project was used to create the infrastructure of this environment. Specify the path of the "terraform.tfvars" file that was used (leave blank if not known): " TFVARSFILE
        TFVARSFILE="${TFVARSFILE/#\~/$HOME}"
    fi
fi
if [ ! -z $TFVARSFILE ]; then
    if [[ $TFVARSFILE != 'unavailable' ]]; then
        TFVARSFILE=$(realpath $TFVARSFILE 2> /dev/null)
        if [ -d $TFVARSFILE ]; then TFVARSFILE="$TFVARSFILE/terraform.tfvars";fi
        if [ ! -f $TFVARSFILE ]; then
            echo "ERROR: --tfvars file '$TFVARSFILE' doesn't exist" | tee -a $logfile
            cleanUp 1
        elif [ $(grep -c '"outputs": {' $TFVARSFILE) -gt 0 ]; then
            echo "ERROR: The '$TFVARSFILE' file specified appears to be a .tfstate file. Please provide the correct path to a .tfvars file instead." | tee -a $logfile
            cleanUp 1
        fi
    else
        TFVARSFILE=''
    fi
fi
echo TFVARSFILE: $TFVARSFILE >> $logfile

# Check if the viya4-deployment project was used
if [ -z $ANSIBLEVARSFILE ]; then
    for ns in $(echo $USER_NS | tr ',' ' '); do
        if $KUBECTLCMD -n $ns get cm sas-deployment-buildinfo > /dev/null 2>&1; then 
            read -p " -> The viya4-deployment project was used to deploy the environment in the '$ns' namespace. Specify the path of the "ansible-vars.yaml" file that was used (leave blank if not known): " ANSIBLEVARSFILE
            ANSIBLEVARSFILE="${ANSIBLEVARSFILE/#\~/$HOME}"
        fi
        if [ ! -z $ANSIBLEVARSFILE ]; then 
            ANSIBLEVARSFILE=$(realpath $ANSIBLEVARSFILE 2> /dev/null)
            if [ -d $ANSIBLEVARSFILE ]; then 
                if [ -f "$ANSIBLEVARSFILE/ansible-vars.yaml" ]; then
                    ANSIBLEVARSFILE="$ANSIBLEVARSFILE/ansible-vars.yaml"
                elif [ -f "$ANSIBLEVARSFILE/ansible-vars-iac.yaml" ]; then
                    ANSIBLEVARSFILE="$ANSIBLEVARSFILE/ansible-vars-iac.yaml"
                else
                    echo "ERROR: ansible-vars.yaml file not found in the '$ANSIBLEVARSFILE' directory" | tee -a $logfile
                    cleanUp 1
                fi
            fi
            if [ ! -f $ANSIBLEVARSFILE ]; then
                echo "ERROR: File '$ANSIBLEVARSFILE' doesn't exist" | tee -a $logfile
                cleanUp 1
            else
                ANSIBLEVARSFILES+=("$ANSIBLEVARSFILE#$ns")
            fi
        fi
    done
elif [[ $ANSIBLEVARSFILE != 'unavailable' ]]; then
    ANSIBLEVARSFILE=$(realpath $ANSIBLEVARSFILE 2> /dev/null)
    if [ -d $ANSIBLEVARSFILE ]; then 
        if [ -f "$ANSIBLEVARSFILE/ansible-vars.yaml" ]; then
            ANSIBLEVARSFILE="$ANSIBLEVARSFILE/ansible-vars.yaml"
        elif [ -f "$ANSIBLEVARSFILE/ansible-vars-iac.yaml" ]; then
            ANSIBLEVARSFILE="$ANSIBLEVARSFILE/ansible-vars-iac.yaml"
        else
            echo "ERROR: ansible-vars.yaml file not found in the '$ANSIBLEVARSFILE' directory" | tee -a $logfile
            cleanUp 1
        fi
    fi
    if [ ! -f $ANSIBLEVARSFILE ]; then
        echo "ERROR: File '$ANSIBLEVARSFILE' doesn't exist" | tee -a $logfile
        cleanUp 1
    else
        # include dac namespace
        dacns=$(grep '^NAMESPACE: ' $ANSIBLEVARSFILE 2>> $logfile | cut -d ' ' -f2)
        # Validate dac namespace
        if echo $dacns | grep -E '^[a-z0-9][-a-z0-9]*[a-z0-9]$' > /dev/null; then
            if [[ ! " ${viyans[*]} " =~ " $dacns " ]]; then
                viyans+=($dacns)
            fi
        else
            dacns='none'
        fi
        ANSIBLEVARSFILES+=("$ANSIBLEVARSFILE#$dacns")
    fi
fi
echo ANSIBLEVARSFILES: ${ANSIBLEVARSFILES[*]} >> $logfile

# Check OUTPATH
if [ -z $OUTPATH ]; then 
    read -p " -> Specify the path where the script output file will be saved ($(pwd)): " OUTPATH
    OUTPATH="${OUTPATH/#\~/$HOME}"
    if [ -z $OUTPATH ]; then OUTPATH=$(pwd); fi
fi
OUTPATH=$(realpath $OUTPATH 2> /dev/null)
echo OUTPATH: $OUTPATH >> $logfile
if [ ! -d $OUTPATH ]; then 
    echo "ERROR: Output path '$OUTPATH' doesn't exist" | tee -a $logfile
    cleanUp 1
else
    outputFile="$OUTPATH/${CASENUMBER}_$(date +"%Y%m%d_%H%M%S").tgz"
    touch $outputFile 2>> $logfile
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to write output file '$outputFile'." | tee -a $logfile
        cleanUp 1
    fi
fi
function removeSensitiveData {
    for file in $@; do
        echo "        - Removing sensitive data from ${file#*/*/*/}" | tee -a $logfile
        isSensitive='false'
        userContent='false'
        # If file isn't empty
        if [ -s "$file" ]; then
            if grep -E \.get-k8s-info.tmp\..{10}/assets/ <<< $file > /dev/null 2>&1; then
                # If file contains Secrets
                if [ $(grep -c '^kind: Secret$' $file) -gt 0 ]; then
                    if [[ $(head -1 $file) != '---' ]]; then
                        sed -i '1i\---' $file
                    fi
                    if [[ $(tail -1 $file) != '---' ]]; then
                        sed -i '$ a\---' $file
                    fi
                    secretStartLines=($(grep -n '^---$\|^kind: Secret$' $file | grep 'kind: Secret' -B1 | grep -v Secret | cut -d ':' -f1))
                    secretEndLines=($(grep -n '^---$\|^kind: Secret$' $file | grep 'kind: Secret' -A1 | grep -v Secret | cut -d ':' -f1))
                    if [[ $[ ${secretStartLines[0]} -1 ] -ne 0 ]]; then
                        sed -n 1,$[ ${secretStartLines[0]} -1 ]p $file > $file.parsed 2>> $logfile
                    fi
                    i=0
                    while [ $i -lt ${#secretStartLines[@]} ]
                    do
                        isSensitive='false'
                        printf '%s\n' "---" >> $file.parsed 2>> $logfile
                        while IFS="" read -r p || [ -n "$p" ]
                        do
                            if [[ $isSensitive == 'true' ]]; then
                                if [[ ${p::2} == '  ' ]]; then
                                    if [[ ${p:2:1} != ' ' ]]; then
                                        printf '%s: %s\n' "${p%%:*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                                    fi
                                else
                                    isSensitive='false'
                                    if [ "${p}" != '---' ]; then printf '%s\n' "${p}" >> $file.parsed 2>> $logfile; fi
                                fi
                            else
                                if [ "${p}" != '---' ]; then printf '%s\n' "${p}" >> $file.parsed 2>> $logfile; fi
                                if grep -q '^data:\|^stringData:' <<< "$p"; then isSensitive='true'; fi
                            fi
                        done < <(sed -n $[ ${secretStartLines[i]} + 1 ],$[ ${secretEndLines[i]} - 1 ]p $file 2>> $logfile)
                        i=$[ $i + 1 ]
                    done
                    printf '%s\n' "---" >> $file.parsed 2>> $logfile
                    sed -n $[ ${secretEndLines[-1]} + 1 ],\$p $file >> $file.parsed 2>> $logfile
                    mv -f $file.parsed $file 2>> $logfile
                fi
                # If file contains SecretGenerators
                if [ $(grep -c '^kind: SecretGenerator$' $file) -gt 0 ]; then
                    if [[ $(head -1 $file) != '---' ]]; then
                        sed -i '1i\---' $file
                    fi
                    if [[ $(tail -1 $file) != '---' ]]; then
                        sed -i '$ a\---' $file
                    fi
                    secretGenStartLines=($(grep -n '^---$\|^kind: SecretGenerator$' $file | grep 'kind: SecretGenerator' -B1 | grep -v SecretGenerator | cut -d ':' -f1))
                    secretGenEndLines=($(grep -n '^---$\|^kind: SecretGenerator$' $file | grep 'kind: SecretGenerator' -A1 | grep -v SecretGenerator | cut -d ':' -f1))
                    if [[ $[ ${secretGenStartLines[0]} -1 ] -ne 0 ]]; then
                        sed -n 1,$[ ${secretGenStartLines[0]} -1 ]p $file > $file.parsed 2>> $logfile
                    fi
                    i=0
                    while [ $i -lt ${#secretGenStartLines[@]} ]
                    do
                        isSensitive='false'
                        isCertificate='false'
                        printf '%s\n' "---" >> $file.parsed 2>> $logfile
                        while IFS="" read -r p || [ -n "$p" ]
                        do
                            if [[ $isSensitive == 'true' ]]; then
                                if [[ "${p}" != '- |' ]]; then
                                    if [[ "${p}" =~ '=' && $isCertificate == 'false' ]]; then
                                        printf '%s=%s\n' "${p%%=*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                                        if [[ "${p}" =~ '-----BEGIN' ]]; then
                                            isCertificate='true'
                                        fi
                                    elif [[ "${p}" =~ '-----END' ]]; then
                                        isCertificate='false'
                                    elif [[ "${p:1:1}" != ' ' ]]; then
                                        isSensitive='false'
                                        printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                                    fi
                                else
                                    printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                                fi
                            else
                                printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                                if grep -q '^literals:' <<< "$p"; then isSensitive='true'; fi
                            fi
                        done < <(sed -n $[ ${secretGenStartLines[i]}+1 ],$[ ${secretGenEndLines[i]}-1 ]p $file 2>> $logfile)
                        i=$[ $i + 1 ]
                    done
                    printf '%s\n' "---" >> $file.parsed 2>> $logfile
                    sed -n $[ ${secretGenEndLines[-1]} + 1 ],\$p $file >> $file.parsed 2>> $logfile
                    mv -f $file.parsed $file 2>> $logfile
                fi
                # If file contains PatchTransformers
                if [ $(grep -c '^kind: PatchTransformer$' $file) -gt 0 ]; then
                    if [[ $(head -1 $file) != '---' ]]; then
                        sed -i '1i\---' $file
                    fi
                    if [[ $(tail -1 $file) != '---' ]]; then
                        sed -i '$ a\---' $file
                    fi
                    patchStartLines=($(grep -n '^---$\|^kind: PatchTransformer$' $file | grep 'kind: PatchTransformer' -B1 | grep -v PatchTransformer | cut -d ':' -f1))
                    patchEndLines=($(grep -n '^---$\|^kind: PatchTransformer$' $file | grep 'kind: PatchTransformer' -A1 | grep -v PatchTransformer | cut -d ':' -f1))
                    if [[ $[ ${patchStartLines[0]} -1 ] -ne 0 ]]; then
                        sed -n 1,$[ ${patchStartLines[0]} -1 ]p $file > $file.parsed 2>> $logfile
                    fi
                    i=0
                    while [ $i -lt ${#patchStartLines[@]} ]
                    do
                        isSensitive='false'
                        inTarget='false'
                        printf '%s\n' "---" >> $file.parsed 2>> $logfile
                        while IFS="" read -r p || [ -n "$p" ]
                        do
                            if [[ "${p}" == 'target:' ]]; then
                                inTarget='true'
                            fi
                            if [[ $inTarget == 'true' && "${p}" == '  kind: Secret' ]]; then
                                isSensitive='true'
                            fi
                        done < <(sed -n $[ ${patchStartLines[i]}+1 ],$[ ${patchEndLines[i]}-1 ]p $file 2>> $logfile)
                        while IFS="" read -r p || [ -n "$p" ]
                        do
                            if [[ $isSensitive == 'true' && "${p}" =~ 'value:' ]]; then
                                printf '%s: %s\n' "${p%%:*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                            else
                                printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                            fi
                        done < <(sed -n $[ ${patchStartLines[i]}+1 ],$[ ${patchEndLines[i]}-1 ]p $file 2>> $logfile)
                        i=$[ $i + 1 ]
                    done
                    printf '%s\n' "---" >> $file.parsed 2>> $logfile
                    sed -n $[ ${patchEndLines[-1]} + 1 ],\$p $file >> $file.parsed 2>> $logfile
                    mv -f $file.parsed $file 2>> $logfile
                fi
            fi
            while IFS="" read -r p || [ -n "$p" ]
            do
                if [ ${file##*/} == 'sas-consul-server_sas-bootstrap-config_kv_read.txt' ]; then
                    # New key
                    if [[ "${p}" =~ 'config/' || "${p}" =~ 'configurationservice/' ]]; then
                        isSensitive='false'
                        isCertificate='false'
                        if [[ "${p}" =~ '-----BEGIN' || "${p}" =~ 'password=' || "${p}" =~ 'Secret=' || "${p}" =~ '"password":"' ]]; then
                            isSensitive='true'
                            if [[ "${p}" =~ '-----BEGIN' ]]; then
                                isCertificate='true'
                            fi
                            printf '%s=%s\n' "${p%%=*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                        elif [[ "${p}" =~ 'pwd=' ]] ;then
                            printf '%s%s%s\n' "${p%%pwd*}" 'pwd={{ sensitive data removed }};' "$(cut -d ';' -f2- <<< ${p##*pwd=})" >> $file.parsed 2>> $logfile
                        else
                            printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                        fi
                    elif [[ "${p::6}" != 'config' ]]; then
                        # Multi-line value
                        isSensitive='false'
                        p_lower=$(tr '[:upper:]' '[:lower:]' <<< ${p})
                        if [[ "${p_lower}" =~ 'password' || "${p_lower}" =~ 'pass' || "${p_lower}" =~ 'pwd' || "${p_lower}" =~ 'secret' || "${p_lower}" =~ 'token' ]]; then
                            printf '%s\n' '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                        elif [ $isCertificate == 'true' ]; then
                            if [[ "${p}" =~ '-----END' ]]; then
                                $isCertificate == 'false'
                            fi
                        else
                            printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                        fi
                    elif [ $isSensitive == 'false' ]; then
                        printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                    fi
                elif [ ${file##*/} == 'terraform.tfvars' ]; then
                    if [[ "${p}" =~ 'secret' || "${p}" =~ 'password' ]]; then
                        printf '%s = %s\n' "${p%%=*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                    else
                        printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                    fi
                elif [[ ${file##*/} =~ 'ansible-vars.yaml' ]]; then
                    if [[ "${p}" =~ 'SECRET' || "${p}" =~ 'PASSWORD' || "${p}" =~ 'password:' ]]; then
                        printf '%s: %s\n' "${p%%:*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                    else
                        printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                    fi
                elif [[ ${file##*/} == 'tasks' || ${file##*/} == 'kubectl_errors.log' ]]; then
                    if [[ "${p}" =~ 'Authorization: ' ]]; then
                        printf "%s'Authorization: %s'%s\n" "${p%%\'*}" '{{ sensitive data removed }}' "${p##*\'}" >> $file.parsed 2>> $logfile
                    else
                        printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                    fi
                else # All other files, including YAML
                    if [[ ( $userContent == 'false' ) && ( "${p}" =~ ':' || "${p}" == '---' ) ]]; then
                        isSensitive='false'
                        # Check for Certificates or HardCoded Passwords
                        if [[ "${p}" =~ '-----BEGIN ' || $p =~ 'ssword: ' ]]; then
                            isSensitive='true'
                            printf '%s: %s\n' "${p%%:*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                        else
                            printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                        fi
                        if [[ "${p}" == '  User Content:' || "${p}" == '  userContent:' || "${p}" == '    userContent:' ]]; then
                            userContent='true'
                            printf '%s\n' '    {{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                        elif [[ "${p}" == '                "userContent": {' ]]; then
                            userContent='true'
                            printf '%s\n' '                    "files": "{{ sensitive data removed }}"' >> $file.parsed 2>> $logfile
                        fi
                    # Print only if not sensitive and not "User content"
                    elif [ $isSensitive == 'false' ]; then
                        if [ $userContent == 'true' ]; then 
                            if [[ "${p}" == 'Status:' || "${p}" == 'status:' || "${p}" == '  status:' ]]; then
                                userContent='false'
                                printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                            elif [[ "${p}" == '            "status": {' ]]; then
                                printf '%s\n' '                    }' >> $file.parsed 2>> $logfile
                                printf '%s\n' '                }' >> $file.parsed 2>> $logfile
                                printf '%s\n' '            },' >> $file.parsed 2>> $logfile
                                userContent='false'
                                printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                            fi
                        else
                            printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                        fi
                    fi
                fi
            done < $file
            rm -f $file 2>> $logfile
            mv -f $file.parsed $file 2>> $logfile
        fi
    done
}
# begin kviya functions
function environmentDetails {
    # Set namespace when executing through get-k8s-info
    if [[ ! -z $1 ]]; then
        ARGNAMESPACE=$1
    fi
    # What Platform?
    if [[ $($KUBECTLCMD get node -l kubernetes.azure.com/cluster -o name | wc -l) -gt 0 ]]; then
        platform='AKS (Microsoft Azure)'
    elif [[ $($KUBECTLCMD get node -l topology.k8s.aws/zone-id -o name | wc -l) -gt 0 ]]; then
        platform='EKS (Amazon AWS)'
    elif [[ $($KUBECTLCMD get node -l topology.gke.io/zone -o name | wc -l) -gt 0 ]]; then
        platform='GKE (Google Cloud)'
    elif [[ $($KUBECTLCMD get node -l node.openshift.io/os_id -o name | wc -l) -gt 0 ]]; then
        ocpPlatform=$($KUBECTLCMD get cm -n kube-system cluster-config-v1 -o yaml 2> /dev/null | grep -A1 '^    platform' | tail -1 | cut -d ':' -f1)
        if [[ $ocpPlatform == 'azure' ]]; then
            platform='Red Hat OpenShift (Azure)'
        elif [[ $ocpPlatform == 'aws' ]]; then
            platform='Red Hat OpenShift (AWS)'
        elif [[ $ocpPlatform == 'openstack' ]]; then
            platform='Red Hat OpenShift (OpenStack)'
        elif [[ $ocpPlatform == 'vsphere' ]]; then
            platform='Red Hat OpenShift (vSphere)'
        elif [[ $ocpPlatform == 'ovirt' ]]; then
            platform='Red Hat OpenShift (oVirt)'
        elif [[ $ocpPlatform == 'baremetal' ]]; then
            platform='Red Hat OpenShift (Bare-metal)'
        else
            platform='Red Hat OpenShift'
        fi
    else
        platform='Bare-metal / Unknown Cloud Platform'
    fi
    # What Region(s)?
    platformRegions=$($KUBECTLCMD get node -o jsonpath={'.items[*].metadata.labels.topology\.kubernetes\.io/region'} 2> /dev/null | tr ' ' '\n' | sort -u | tr '\n' ' ')
    # What Zone(s)?
    platformZones=$($KUBECTLCMD get node -o jsonpath={'.items[*].metadata.labels.topology\.kubernetes\.io/zone'} 2> /dev/null | tr ' ' '\n' | sort -u | tr '\n' ' ')
    # What Kubernetes Version?
    serverVersion=$($KUBECTLCMD version -o yaml 2>/dev/null | grep serverVersion -A9 | grep gitVersion | cut -d ' ' -f4 | cut -d '+' -f1)
    ocpVersion=$($KUBECTLCMD version -o yaml 2>/dev/null | grep openshiftVersion | cut -d ' ' -f2)
    clientVersion=$($KUBECTLCMD version -o yaml 2>/dev/null | grep clientVersion -A9 | grep gitVersion | cut -d ' ' -f4 | cut -d '+' -f1 | cut -d '-' -f1)

    # Viya Details
    # Version
    deploymentCm=($($KUBECTLCMD get cm -n $ARGNAMESPACE -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2> /dev/null | grep ' sas-deployment-metadata-' | sort -k1 -t ' ' -r | awk '{print $2}'))
    viyaCadence=$($KUBECTLCMD -n $ARGNAMESPACE get cm ${deploymentCm[0]} -o jsonpath='{.data.SAS_CADENCE_DISPLAY_NAME}' 2> /dev/null)
    viyaRelease=$($KUBECTLCMD -n $ARGNAMESPACE get cm ${deploymentCm[0]} -o jsonpath='{.data.SAS_CADENCE_RELEASE}' 2> /dev/null)
    if [[ ${#deploymentCm[@]} -gt 1 ]]; then
        viyaVersion="$viyaCadence (Release $viyaRelease) WARNING: Multiple sas-deployment-metadata ConfigMap exist. The information was captured from ${deploymentCm[0]}"
    else
        viyaVersion="$viyaCadence (Release $viyaRelease)"
    fi
    # Deployment Method
    if $KUBECTLCMD -n $ARGNAMESPACE get cm sas-deployment-buildinfo > /dev/null 2>&1; then
        deploymentMethod='dac'
    fi
    if [[ $($KUBECTLCMD -n $ARGNAMESPACE get sasdeployment -o name 2> /dev/null | wc -l) -gt 0 ]]; then
        if [[ $deploymentMethod == 'dac' ]]; then
            deploymentMethod='DaC Github Project (SAS Deployment Operator)'
        else
            deploymentMethod='SAS Deployment Operator'
        fi
    else
        if [[ $deploymentMethod == 'dac' ]]; then
            deploymentMethod='DaC Github Project (sas-orchestration)'
        else
            deploymentMethod='Manual / sas-orchestration'
        fi
    fi
    # Ingress
    ingressCm=($($KUBECTLCMD get cm -n $ARGNAMESPACE -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2> /dev/null | grep ' ingress-input-' | sort -k1 -t ' ' -r | awk '{print $2}'))
    viyaIngress=$($KUBECTLCMD -n $ARGNAMESPACE get cm ${ingressCm[0]} -o jsonpath='{.data.INGRESS_HOST}' 2> /dev/null)
    if [[ ${#ingressCm[@]} -gt 1 ]]; then
        viyaIngress="$viyaIngress (WARNING: Multiple ingress-input ConfigMap exist. The information was captured from ${ingressCm[0]})"
    fi
    tlsMode=$($KUBECTLCMD -n $ARGNAMESPACE get deploy sas-logon-app -o jsonpath='{.metadata.annotations.sas\.com/tls-mode}' 2> /dev/null)
    if [[ $? -eq 0 && -z $tlsMode ]]; then tlsMode='No TLS'; fi
    # Ingress Certificate
    ingressCertificateSecret=($($KUBECTLCMD get secret -n $ARGNAMESPACE -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2> /dev/null | grep ' sas-ingress-certificate' | sort -k1 -t ' ' -r | awk '{print $2}'))
    if [[ ! -z $ingressCertificateSecret[@] ]]; then
        if openssl x509 -text -noout <<< $($KUBECTLCMD -n $ARGNAMESPACE get secret ${ingressCertificateSecret[0]} -o jsonpath='{.data.tls\.crt}' 2> /dev/null | base64 -d 2> /dev/null) | grep 'Issuer: ' | grep sas-viya-root-ca-certificate > /dev/null ; then
            ingressCertificate='Generated'
        else
            ingressCertificate='Customer Provided'
        fi
    else
        ingressCertificate=''
    fi
    if [[ ${#ingressCertificateSecret[@]} -gt 1 ]]; then
        ingressCertificate="$ingressCertificate (WARNING: Multiple sas-ingress-certificate Secret exist. The information was captured from ${ingressCertificateSecret[0]})"
    fi
    # Order
    lifecycleSecret=($($KUBECTLCMD get secret -n $ARGNAMESPACE -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2> /dev/null | grep ' sas-lifecycle-image-' | sort -k1 -t ' ' -r | awk '{print $2}'))
    viyaOrder=$($KUBECTLCMD -n $ARGNAMESPACE get secret ${lifecycleSecret[0]} -o jsonpath='{.data.username}' 2> /dev/null | base64 -d 2> /dev/null)
    if [[ ${#lifecycleSecret[@]} -gt 1 ]]; then
        viyaOrder="$viyaOrder (WARNING: Multiple sas-lifecycle-image Secret exist. The information was captured from ${lifecycleSecret[0]})"
    fi
    # Site Number
    licenseSecret=($($KUBECTLCMD get secret -n $ARGNAMESPACE -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2> /dev/null | grep ' sas-license-' | sort -k1 -t ' ' -r | awk '{print $2}'))
    viyaSiteNum=$($KUBECTLCMD -n $ARGNAMESPACE get secret ${licenseSecret[0]} -o jsonpath='{.data.SAS_LICENSE}' 2> /dev/null | base64 -d 2> /dev/null | cut -d '.' -f2 | base64 -d 2> /dev/null | tr ',' '\n' | grep '^"siteNumber":"' | cut -d '"' -f4)
    if [[ ${#licenseSecret[@]} -gt 1 ]]; then
        viyaSiteNum="$viyaSiteNum (WARNING: Multiple sas-license Secret exist. The information was captured from ${licenseSecret[0]})"
    fi
    # License Expiration
    viyaExpiration=$($KUBECTLCMD -n $ARGNAMESPACE get secret ${licenseSecret[0]} -o jsonpath='{.data.SAS_LICENSE}' 2> /dev/null | base64 -d 2> /dev/null | cut -d '.' -f2 | base64 -d 2> /dev/null | tr ' ' '\n' | grep '^EXPIRE=' | cut -d "'" -f2)
    if [[ ${#licenseSecret[@]} -gt 1 ]]; then
        viyaExpiration="$viyaExpiration (WARNING: Multiple sas-license Secret exist. The information was captured from ${licenseSecret[0]})"
    fi
    # PostgreSQL
    viyaPostgreSQL=$($KUBECTLCMD -n $ARGNAMESPACE get dataserver sas-platform-postgres -o jsonpath={.spec.registrations[0].host} 2> /dev/null)
    if [[ $viyaPostgreSQL == 'sas-crunchy-platform-postgres-primary' ]]; then
        viyaPostgreSQL='Internal Crunchy Data'
    else
        viyaPostgreSQL="$viyaPostgreSQL (External)"
    fi
    # CAS
    casMode=$($KUBECTLCMD -n $ARGNAMESPACE get casdeployment default -o jsonpath='{.spec.workers}' 2> /dev/null)
    if [[ $casMode -eq 0 ]]; then
        casMode='SMP'
    else
        casMode="MPP ($casMode Workers)"
    fi
    casCacheDirs=($($KUBECTLCMD -n $ARGNAMESPACE get casdeployment default -o jsonpath='{.spec.controllerTemplate.spec.containers[0].env[?(@.name=="CASENV_CAS_DISK_CACHE")].value}' 2> /dev/null | tr ':' '\n'))
    casCacheVolumeMounts=()
    if [[ -z $casCacheDirs ]]; then
	    casCacheVolumeMounts=($($KUBECTLCMD -n $ARGNAMESPACE get casdeployment default -o jsonpath='{.spec.controllerTemplate.spec.containers[0].volumeMounts[?(@.mountPath=="/cas/cache")].name}' 2> /dev/null))
    else
        for casCacheDir in ${casCacheDirs[@]}; do
            casCacheVolumeMounts+=($($KUBECTLCMD -n $ARGNAMESPACE get casdeployment default -o jsonpath="{.spec.controllerTemplate.spec.containers[0].volumeMounts[?(@.mountPath=='$casCacheDir')].name}" 2> /dev/null))
        done
    fi
    casCacheVolumeTypes=()
    for casCacheVolumeMount in ${casCacheVolumeMounts[@]}; do
        casCacheVolumeTypes+=($($KUBECTLCMD -n $ARGNAMESPACE get casdeployment default -o jsonpath="{.spec.controllerTemplate.spec.volumes[?(@.name=='$casCacheVolumeMount')]}" 2> /dev/null | tr ',' '\n' | grep -v '"name":"' | head -1 | cut -d '"' -f2))
    done
    casCacheVolumeTypes="$(tr ' ' '\n' <<< ${casCacheVolumeTypes[@]} | sort -u | tr '\n' ' ')"
    # Work
    sharedConfigCm=($($KUBECTLCMD get cm -n $ARGNAMESPACE -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2> /dev/null | grep ' sas-shared-config-' | sort -k1 -t ' ' -r | awk '{print $2}'))
    allowAdminScripts=$($KUBECTLCMD -n $ARGNAMESPACE get cm ${sharedConfigCm[0]} -o jsonpath='{.data.SAS_ALLOW_ADMIN_SCRIPTS}' 2> /dev/null)
    if [[ $allowAdminScripts == 'true' ]]; then
        # Look for SAS Work customizations
        batchWork=$($KUBECTLCMD -n $ARGNAMESPACE exec sas-consul-server-0 -c sas-consul-server -- bash -c "export CONSUL_HTTP_ADDR=\$SAS_URL_SERVICE_SCHEME://localhost:8500;/opt/sas/viya/home/bin/sas-bootstrap-config kv read 'config/batch/sas.batch.server/configuration_options/contents'" 2> /dev/null | grep -i '^-work ' | cut -d ' ' -f2)
        computeWork=$($KUBECTLCMD -n $ARGNAMESPACE exec sas-consul-server-0 -c sas-consul-server-0 -- bash -c "export CONSUL_HTTP_ADDR=\$SAS_URL_SERVICE_SCHEME://localhost:8500;/opt/sas/viya/home/bin/sas-bootstrap-config kv read 'config/batch/sas.compute.server/configuration_options/contents'" 2> /dev/null | grep -i '^-work ' | cut -d ' ' -f2)
        connectWork=$($KUBECTLCMD -n $ARGNAMESPACE exec sas-consul-server-0 -c sas-consul-server-0 -- bash -c "export CONSUL_HTTP_ADDR=\$SAS_URL_SERVICE_SCHEME://localhost:8500;/opt/sas/viya/home/bin/sas-bootstrap-config kv read 'config/batch/sas.connect.server/configuration_options/contents'" 2> /dev/null | grep -i '^-work ' | cut -d ' ' -f2)
    fi
    if [[ -z $batchWork ]]; then
        batchWork='/opt/sas/viya/config/var'
    elif [[ ${batchWork: -1} == '/' ]]; then
        batchWork=${batchWork::-1}
    fi
    if [[ -z $computeWork ]]; then
        computeWork='/opt/sas/viya/config/var'
    elif [[ ${computeWork: -1} == '/' ]]; then
        computeWork=${computeWork::-1}
    fi
    if [[ -z $connectWork ]]; then
        connectWork='/opt/sas/viya/config/var'
    elif [[ ${connectWork: -1} == '/' ]]; then
        connectWork=${connectWork::-1}
    fi
    batchWorkVolumeMount=$($KUBECTLCMD -n $ARGNAMESPACE get podtemplate sas-batch-pod-template -o jsonpath="{.template.spec.containers[0].volumeMounts[?(@.mountPath=='$batchWork')].name}" 2> /dev/null)
    computeWorkVolumeMount=$($KUBECTLCMD -n $ARGNAMESPACE get podtemplate sas-compute-job-config -o jsonpath="{.template.spec.containers[0].volumeMounts[?(@.mountPath=='$computeWork')].name}" 2> /dev/null)
    connectWorkVolumeMount=$($KUBECTLCMD -n $ARGNAMESPACE get podtemplate sas-connect-pod-template -o jsonpath="{.template.spec.containers[0].volumeMounts[?(@.mountPath=='$connectWork')].name}" 2> /dev/null)

    batchWorkVolumeType=$($KUBECTLCMD -n $ARGNAMESPACE get podtemplate sas-batch-pod-template -o jsonpath="{.template.spec.volumes[?(@.name=='$batchWorkVolumeMount')]}" 2> /dev/null | tr ',' '\n' | grep -v '"name":"' | head -1 | cut -d '"' -f2)
    computeWorkVolumeType=$($KUBECTLCMD -n $ARGNAMESPACE get podtemplate sas-compute-job-config  -o jsonpath="{.template.spec.volumes[?(@.name=='$computeWorkVolumeMount')]}" 2> /dev/null | tr ',' '\n' | grep -v '"name":"' | head -1 | cut -d '"' -f2)
    connectWorkVolumeType=$($KUBECTLCMD -n $ARGNAMESPACE get podtemplate sas-connect-pod-template -o jsonpath="{.template.spec.volumes[?(@.name=='$connectWorkVolumeMount')]}" 2> /dev/null | tr ',' '\n' | grep -v '"name":"' | head -1 | cut -d '"' -f2)
    # Certificate Generator
    certframeCm=($($KUBECTLCMD get cm -n $ARGNAMESPACE -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2> /dev/null | grep ' sas-certframe-user-config-' | sort -k1 -t ' ' -r | awk '{print $2}'))
    viyaCertGenerator=$($KUBECTLCMD -n $ARGNAMESPACE get cm ${certframeCm[0]} -o jsonpath='{.data.SAS_CERTIFICATE_GENERATOR}' 2> /dev/null)
    if [[ ${#certframeCm[@]} -gt 1 ]]; then
        viyaCertGenerator="$viyaCertGenerator (WARNING: Multiple sas-certframe-user-config ConfigMap exist. The information was captured from ${certframeCm[0]})"
    fi
    #Storage Classes
    scVarLen=(0 0)
    scNames=($($KUBECTLCMD -n $ARGNAMESPACE get pvc -o jsonpath='{.items[*].spec.storageClassName}' 2> /dev/null | tr ' ' '\n' | sort -u))
    for scIndex in ${!scNames[@]}; do
        if [ $[ ${#scNames[$scIndex]} + 2 ] -gt ${scVarLen[0]} ]; then
            scVarLen[0]=$[ ${#scNames[$scIndex]} + 2 ]
        fi
        scProvisioner[$scIndex]=$($KUBECTLCMD get sc ${scNames[$scIndex]} -o jsonpath='{.provisioner}')
        if [ $[ ${#scProvisioner[$scIndex]} + 2 ] -gt ${scVarLen[1]} ]; then
            scVarLen[1]=$[ ${#scProvisioner[$scIndex]} + 2 ]
        fi
        scParameters[$scIndex]=$($KUBECTLCMD get sc ${scNames[$scIndex]} -o jsonpath='{.parameters}')
    done
    # Print Report
    echo -e "\nKubernetes Cluster"
    echo -e "------------------"
    printf "%-25s %-s\n" 'Cloud Platform:' "$platform"
    printf "%-25s %-s\n" 'Region(s):' "$platformRegions"
    printf "%-25s %-s\n" 'Zone(s):' "$platformZones"
    if [[ -z $ocpVersion ]]; then
        printf "%-25s %-s\n" 'Kubernetes Server:' "$serverVersion"
    else
        printf "%-25s %-s\n" 'Kubernetes Server:' "$serverVersion (OpenShift $ocpVersion)"
    fi
    printf "%-25s %-s\n" 'Kubernetes Client:' "$clientVersion"
    echo -e "\nViya Environment"
    echo -e "----------------"
    printf "%-25s %-s\n" 'Namespace:' "$ARGNAMESPACE"
    printf "%-25s %-s\n" 'Deployment Method:' "$deploymentMethod"
    printf "%-25s %-s\n" 'Version:' "$viyaVersion"
    printf "%-25s %-s\n" 'Order:' "$viyaOrder"
    printf "%-25s %-s\n" 'Site Number:' "$viyaSiteNum"
    printf "%-25s %-s\n" 'License Expires:' "$viyaExpiration"
    printf "%-25s %-s\n" 'CAS Mode:' "$casMode"
    printf "%-25s %-s\n" 'CAS Disk Cache:' "$casCacheVolumeTypes"
    printf "%-25s %-s\n" 'SAS Work:' "sas-batch: $batchWorkVolumeType   sas-compute: $computeWorkVolumeType   sas-connect: $connectWorkVolumeType"
    printf "%-25s %-s\n" 'PostgreSQL Database:' "$viyaPostgreSQL"
    printf "%-25s %-s\n" 'TLS Mode:' "$tlsMode"
    printf "%-25s %-s\n" 'Certificate Generator:' "$viyaCertGenerator"
    printf "%-25s %-s\n" 'Ingress Host:' "$viyaIngress"
    printf "%-25s %-s\n" 'Ingress Certificate:' "$ingressCertificate"
    echo -e "Storage Classes in Use:"
    printf "\n  %-${scVarLen[0]}s %-${scVarLen[1]}s %-s\n" 'NAME' 'PROVISIONER' 'PARAMETERS'
    printf "  %-${scVarLen[0]}s %-${scVarLen[1]}s %-s\n" '----' '-----------' '----------'
    for scIndex in ${!scNames[@]}; do
        printf "  %-${scVarLen[0]}s %-${scVarLen[1]}s %-s\n" "${scNames[$scIndex]}" "${scProvisioner[$scIndex]}" "${scParameters[$scIndex]}"
    done
}
function nodeMon {
    ## Node Monitoring

    if [ "$ARGPLAYBACK" == 'false' ]; then 
        $KUBECTLCMD get node > $TEMPDIR/.kviya/work/getnodes.out 2> /dev/null
        $KUBECTLCMD describe node > $TEMPDIR/.kviya/work/nodes-describe.out 2> /dev/null
        $KUBECTLCMD top node > $TEMPDIR/.kviya/work/nodesTop.out 2> /dev/null
    fi

    csplit --prefix $TEMPDIR/.kviya/work/k8snode --quiet --suppress-matched -z $TEMPDIR/.kviya/work/nodes-describe.out "/^$/" '{*}'

    nodeCount=0
    for file in $(ls $TEMPDIR/.kviya/work/k8snode*); do
        nodeFiles[$nodeCount]=$file
        nodeNames[$nodeCount]=$(grep ^Name: $file | grep ^Name: | awk '{print $2}')
        nodeStatuses[$nodeCount]=$(grep "${nodeNames[$nodeCount]} " $TEMPDIR/.kviya/work/getnodes.out | awk '{print $2}')
        nodeTaints[$nodeCount]=$(grep '  workload.sas.com/class' $file | grep NoSchedule | cut -d '=' -f2 | cut -d ':' -f1)
        nodeLabels[$nodeCount]=$(grep '  workload.sas.com/class' $file | grep -v NoSchedule | cut -d '=' -f2)
        zone=$(grep '  topology.kubernetes.io/zone' $file | cut -d '=' -f2)
        region=$(grep '  topology.kubernetes.io/region' $file | cut -d '=' -f2)
        if [[ $zone =~ $region ]]; then 
            nodeZone[$nodeCount]=$zone
        elif [[ ! -z $zone && ! -z $region ]]; then
            nodeZone[$nodeCount]=$region-$zone
        fi
        nodeVm[$nodeCount]=$(grep '  node.kubernetes.io/instance-type' $file | cut -d '=' -f2)
        for condition in $(grep 'NetworkUnavailable\|MemoryPressure\|DiskPressure\|PIDPressure\|Unschedulable' $file | grep -i true | awk -F'[:]' '{print $1}' | awk '{print $1}'); do
            if [ ${#nodeConditions[$nodeCount]} = 0 ]; then 
                nodeConditions[$nodeCount]=$condition
            else 
                nodeConditions[$nodeCount]=${nodeConditions[$nodeCount]},$condition
            fi
        done
        nodePods[$nodeCount]=$(grep 'Non-terminated Pods' $file | awk -F' *[( ]' '{print $3}')/$(awk '/Allocatable:/, /pods/' $file | grep pods | awk -F' *' '{print $3}')
        nodeResources[$nodeCount]=$(grep -A5 'Allocated resources' $file | tail -2 | awk '{print $2, $3}' | tr '\n' '\t' | tr '()' ' ' | awk '{if ($3 ~ /Mi/) print $1, $2, "/", $4, $3; else if ($3 ~ /Ki/) print $1, $2, "/", $4, int( int($3) / 1024 )"Mi"; else if ($3 ~ /Gi/) print $1, $2, "/", $4, int( int($3) * 1024 )"Mi";else print $1, $2, "/", $4, int( $3 / 1048576 )"Mi";}')
        nodeTop[$nodeCount]=$(grep ${nodeNames[$nodeCount]} $TEMPDIR/.kviya/work/nodesTop.out | awk '{print $3,"/", $5}')
        if [[ ${#nodeTop[$nodeCount]} -eq 0 || ${nodeTop[$nodeCount]} == '<unknown> / <unknown>' ]];then nodeTop[$nodeCount]='- / -';fi

        if [[ -z ${nodeConditions[$nodeCount]} ]]; then nodeConditions[$nodeCount]='OK';fi
        if [[ -z ${nodeLabels[$nodeCount]} ]]; then nodeLabels[$nodeCount]='-';fi
        if [[ -z ${nodeTaints[$nodeCount]} ]]; then nodeTaints[$nodeCount]='-';fi
        if [[ -z ${nodeZone[$nodeCount]} ]]; then nodeZone[$nodeCount]='-';fi
        if [[ -z ${nodeVm[$nodeCount]} ]]; then nodeVm[$nodeCount]='-';fi

        nodeCount=$[ $nodeCount + 1 ]
    done

    # Find length of each column
    nodeVarLen=(6 8 11 7 7 6 6 4)

    for VALUE in ${nodeNames[@]}; do
        if [ $[ ${#VALUE} + 2 ] -gt ${nodeVarLen[0]} ]; then
            nodeVarLen[0]=$[ ${#VALUE} + 2 ]
        fi
    done

    readynodes=0
    for VALUE in ${nodeStatuses[@]}; do
        if [ $[ ${#VALUE} + 2 ] -gt ${nodeVarLen[1]} ]; then
            nodeVarLen[1]=$[ ${#VALUE} + 2 ]
        fi
        if [ $VALUE == 'Ready' ]; then readynodes=$[ $readynodes + 1 ]; fi
    done
    for VALUE in ${nodeConditions[@]}; do
        if [ $[ ${#VALUE} + 2 ] -gt ${nodeVarLen[2]} ]; then
            nodeVarLen[2]=$[ ${#VALUE} + 2 ]
        fi
    done
    for VALUE in ${nodeLabels[@]}; do
        if [ $[ ${#VALUE} + 2 ] -gt ${nodeVarLen[3]} ]; then
            nodeVarLen[3]=$[ ${#VALUE} + 2 ]
        fi
    done
    for VALUE in ${nodeTaints[@]}; do
        if [ $[ ${#VALUE} + 2 ] -gt ${nodeVarLen[4]} ]; then
            nodeVarLen[4]=$[ ${#VALUE} + 2 ]
        fi
    done
    for VALUE in ${nodePods[@]}; do
        if [ $[ ${#VALUE} + 0 ] -gt ${nodeVarLen[5]} ]; then
            nodeVarLen[5]=$[ ${#VALUE} + 0 ]
        fi
    done
    for VALUE in ${nodeZone[@]}; do
        if [ $[ ${#VALUE} + 2 ] -gt ${nodeVarLen[6]} ]; then
            nodeVarLen[6]=$[ ${#VALUE} + 2 ]
        fi
    done
    for VALUE in ${nodeVm[@]}; do
        if [ $[ ${#VALUE} + 2 ] -gt ${nodeVarLen[7]} ]; then
            nodeVarLen[7]=$[ ${#VALUE} + 2 ]
        fi
    done

    echo -e "\nKubernetes Nodes ($readynodes/$nodeCount)\n" > $TEMPDIR/.kviya/work/nodeMon.out
    printf "%-${nodeVarLen[0]}s %-${nodeVarLen[1]}s %-${nodeVarLen[2]}s %-${nodeVarLen[3]}s %-${nodeVarLen[4]}s %-${nodeVarLen[7]}s %-${nodeVarLen[6]}s %${nodeVarLen[5]}s %12s %-s\n" 'NAME' 'STATUS' 'CONDITION' 'LABEL' 'TAINT' 'VM' 'ZONE' 'PODS' '  TOP (CPU / MEMORY)' '  REQUESTS (CPU / MEMORY)' >> $TEMPDIR/.kviya/work/nodeMon.out

    for (( nodeCount=0; nodeCount<${#nodeFiles[@]}; nodeCount++ )); do
        printf "%-${nodeVarLen[0]}s %-${nodeVarLen[1]}s %-${nodeVarLen[2]}s %-${nodeVarLen[3]}s %-${nodeVarLen[4]}s %-${nodeVarLen[7]}s %-${nodeVarLen[6]}s %${nodeVarLen[5]}s %10s %1s %4s %13s %4s %s %4s %8s\n" ${nodeNames[$nodeCount]} ${nodeStatuses[$nodeCount]} ${nodeConditions[$nodeCount]} ${nodeLabels[$nodeCount]} ${nodeTaints[$nodeCount]} ${nodeVm[$nodeCount]} ${nodeZone[$nodeCount]} ${nodePods[$nodeCount]} ${nodeTop[$nodeCount]} ${nodeResources[$nodeCount]} >> $TEMPDIR/.kviya/work/nodeMon.out
        
        if [ "$ARGNODEEVENTS" == 'true' ]; then
            awk '/^Events:/,0' ${nodeFiles[$nodeCount]} | awk '/-------/,0' | grep -v '\-\-\-\-\-\-\-' > $TEMPDIR/.kviya/work/${nodeNames[$nodeCount]}-events.out
            if [ -s $TEMPDIR/.kviya/work/${nodeNames[$nodeCount]}-events.out ]; then
                cat $TEMPDIR/.kviya/work/${nodeNames[$nodeCount]}-events.out >> $TEMPDIR/.kviya/work/nodeMon.out
                echo '' >> $TEMPDIR/.kviya/work/nodeMon.out
            fi
        fi
    done
    unset nodeNames nodeStatuses nodeTaints nodeLabels nodeConditions nodePods nodeTop nodeResources nodeZone nodeVm
    rm -f $TEMPDIR/.kviya/work/k8snode*
}
function podMon {
    ## Pod Monitoring

    # Collect initial pod list
    if [ "$ARGPLAYBACK" == 'false' ]; then 
        $KUBECTLCMD -n $ARGNAMESPACE get pod -o wide > $TEMPDIR/.kviya/work/getpod.out 2> /dev/null
    fi
    
    # Totals
    TOTAL=$(grep -v 'Completed\|NAME' -c $TEMPDIR/.kviya/work/getpod.out)

    grep -v '1/1\|2/2\|3/3\|4/4\|5/5\|6/6\|7/7\|8/8\|9/9\|Completed\|Terminating\|NAME' $TEMPDIR/.kviya/work/getpod.out | sed 's/<none> *$//' | sed 's/<none> *$//' > $TEMPDIR/.kviya/work/notready.out
    grep 'Terminating' $TEMPDIR/.kviya/work/getpod.out | sed 's/<none> *$//' | sed 's/<none> *$//' >> $TEMPDIR/.kviya/work/notready.out
    NOTREADY=$(wc -l $TEMPDIR/.kviya/work/notready.out | awk '{print $1}')

    echo -e "" > $TEMPDIR/.kviya/work/podMon.out
    echo $(echo -e "Pods ($[ $TOTAL-$NOTREADY ]/$TOTAL):";grep -v NAME $TEMPDIR/.kviya/work/getpod.out | awk '{print $3}' | sort | uniq -c | sort -nr | tr '\n' ',' | sed 's/.$//') >> $TEMPDIR/.kviya/work/podMon.out

    # Check Pods
    if [ $NOTREADY -gt 0 ] || [ $ARGREADYPODS == 'true' ] || [ ! -z "${ARGPODGREP}" ]; then
        echo '' >> $TEMPDIR/.kviya/work/podMon.out

        if [ $ARGREADYPODS == 'true' ] || [ ! -z "${ARGPODGREP}" ]; then
            grep -v 'NAME' $TEMPDIR/.kviya/work/getpod.out | grep -E "${ARGPODGREP}" | sed 's/<none> *$//' | sed 's/<none> *$//' > $TEMPDIR/.kviya/work/notready.out
        fi

        # Count pods
        PENDING=$(grep -c "Pending" $TEMPDIR/.kviya/work/notready.out)
        CONSUL=$(grep -c "sas-consul" $TEMPDIR/.kviya/work/notready.out)
        POSTGRES=$(grep -c "sas-crunchy\|sas-data-server-operator" $TEMPDIR/.kviya/work/notready.out)
        RABBIT=$(grep -c "sas-rabbitmq" $TEMPDIR/.kviya/work/notready.out)
        CACHE=$(grep -c "sas-cache\|sas-redis" $TEMPDIR/.kviya/work/notready.out)
        CAS=$(grep -c "sas-cas-" $TEMPDIR/.kviya/work/notready.out)
        LOGON=$(grep -c "sas-logon-app" $TEMPDIR/.kviya/work/notready.out)
        CONFIG=$(grep -c "sas-configuration" $TEMPDIR/.kviya/work/notready.out)
        OTHER=$[ $NOTREADY-$PENDING-$CONSUL-$POSTGRES-$RABBIT-$CACHE-$CAS-$LOGON-$CONFIG ]

        head -1 $TEMPDIR/.kviya/work/getpod.out | sed 's/NOMINATED NODE//' | sed 's/READINESS GATES//' >> $TEMPDIR/.kviya/work/podMon.out
        if [ "$ARGPODEVENTS" == 'true' ]; then 
            function printPods {
                grep "$pod" $TEMPDIR/.kviya/work/notready.out >> $TEMPDIR/.kviya/work/podMon.out
                if [ $(grep -c "pod/$pod" $TEMPDIR/.kviya/work/podevents.out) -gt 0 ]; then
                    if [ "$ARGLASTPODEVENT" == 'false' ]; then
                        grep "pod/$pod" $TEMPDIR/.kviya/work/podevents.out | awk '{if ($6 ~ /kubelet/) print $1,$2,$3,$7; else print $1,$2,$3,$5'} OFS="\t" FS="[[:space:]][[:space:]]+" | sed -e 's/^/  /' >> $TEMPDIR/.kviya/work/podMon.out
                    else
                        grep "pod/$pod" $TEMPDIR/.kviya/work/podevents.out | tail -1 | awk '{if ($6 ~ /kubelet/) print $1,$2,$3,$7; else print $1,$2,$3,$5'} OFS="\t" FS="[[:space:]][[:space:]]+" | sed -e 's/^/  /' >> $TEMPDIR/.kviya/work/podMon.out
                    fi
                    echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                fi
            }
            if [ "$ARGPLAYBACK" == 'false' ]; then 
                $KUBECTLCMD get events > $TEMPDIR/.kviya/work/podevents.out 2> /dev/null
            fi
            
            if [ $PENDING -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "Pending" $TEMPDIR/.kviya/work/notready.out | awk '{print $1}'); do printPods; done
            fi
            if [ $CONSUL -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "sas-consul" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" | awk '{print $1}'); do printPods; done
            fi
            if [ $POSTGRES -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "sas-crunchy\|sas-data-server-operator" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" | awk '{print $1}'); do printPods; done
            fi
            if [ $RABBIT -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "sas-rabbitmq" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" | awk '{print $1}'); do printPods; done
            fi
            if [ $CACHE -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "sas-cache\|sas-redis" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" | awk '{print $1}'); do printPods; done
            fi
            if [ $CAS -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "sas-cas-" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" | awk '{print $1}'); do printPods; done
            fi
            if [ $LOGON -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "sas-logon-app" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" | awk '{print $1}'); do printPods; done
            fi
            if [ $CONFIG -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep "sas-configuration" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" | awk '{print $1}'); do printPods; done
            fi
            if [ $OTHER -gt 0 ] || [ $ARGREADYPODS == 'true' ] || [ ! -z "${ARGPODGREP}" ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                for pod in $(grep -v "Pending\|sas-consul\|sas-crunchy\|sas-data-server-operator\|sas-rabbitmq\|sas-cache\|sas-redis\|sas-cas-\|sas-logon-app\|sas-configuration" $TEMPDIR/.kviya/work/notready.out | awk '{print $1}'); do printPods; done
            fi
        else
            if [ $PENDING -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "Pending" $TEMPDIR/.kviya/work/notready.out >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $CONSUL -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "sas-consul" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $POSTGRES -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "sas-crunchy\|sas-data-server-operator" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $RABBIT -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "sas-rabbitmq" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $CACHE -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "sas-cache\|sas-redis" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $CAS -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "sas-cas-" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $LOGON -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "sas-logon-app" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $CONFIG -gt 0 ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep "sas-configuration" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
            if [ $OTHER -gt 0 ] || [ $ARGREADYPODS == 'true' ] || [ ! -z "${ARGPODGREP}" ]; then
                echo -e "" >> $TEMPDIR/.kviya/work/podMon.out
                grep -v "Pending\|sas-consul\|sas-crunchy\|sas-data-server-operator\|sas-rabbitmq\|sas-cache\|sas-redis\|sas-cas-\|sas-logon-app\|sas-configuration" $TEMPDIR/.kviya/work/notready.out | grep -v "Pending" >> $TEMPDIR/.kviya/work/podMon.out
            fi
        fi
    fi
}
# end kviya functions
function kviyaReport {
    # kviya variables
    ARGPLAYBACK='true'
    ARGNODEEVENTS='false'
    ARGPODEVENTS='false'
    ARGLASTPODEVENT='false'
    ARGREADYPODS='true'
    ARGPODGREP=''

    namespace=$1
    mkdir -p $TEMPDIR/.kviya/work $TEMPDIR/reports
    cp -r $TEMPDIR/kubernetes/$namespace/.kviya/$(ls $TEMPDIR/kubernetes/$namespace/.kviya | grep -Ei '[0-9]{4}D[0-9]{2}D[0-9]{2}_[0-9]{2}T[0-9]{2}T[0-9]{2}$')/* $TEMPDIR/.kviya/work
    nodeMon; podMon
    cat $TEMPDIR/.kviya/work/environmentDetails.out $TEMPDIR/.kviya/work/nodeMon.out $TEMPDIR/.kviya/work/podMon.out > $TEMPDIR/reports/kviya-report_$namespace.txt
    rm -rf $TEMPDIR/.kviya/work
}
function nodesTimeReport {
    mkdir -p $TEMPDIR/.get-k8s-info/nodesTimeReport

    # Check time sync between nodes
    echo -e "Nodes Time Report\n" > $TEMPDIR/reports/nodes-time-report.txt
    nodes=($($KUBECTLCMD get node -o name 2>> $logfile | cut -d '/' -f2))
    nodeTimePods=()

    # Look for pods running on each node that have the 'date' command available
    for nodeIndex in ${!nodes[@]}; do
        for pod in $($KUBECTLCMD get pod --all-namespaces -o wide 2>> $logfile | grep " Running " | grep " ${nodes[$nodeIndex]} " | awk '{print $1"/"$2}'); do
            if $timeoutCmd 10 $KUBECTLCMD -n ${pod%%/*} exec ${pod#*/} -- date -u > /dev/null 2>&1; then
                nodeTimePods[$nodeIndex]=$pod
                break
            fi
        done
    done

    # Collect date from all nodes headless
    for nodeIndex in ${!nodes[@]}; do
        nodeTimePod=${nodeTimePods[$nodeIndex]}
        if [[ ! -z $nodeTimePod ]]; then
            $KUBECTLCMD -n ${nodeTimePod%%/*} exec ${nodeTimePod#*/} -- date -u > $TEMPDIR/.get-k8s-info/nodesTimeReport/node$nodeIndex.out 2>> $logfile &
        fi
    done
    date -u > $TEMPDIR/.get-k8s-info/nodesTimeReport/jump.out 2>> $logfile &

    # Wait for results
    countWait=0
    countReady=0
    while [[ $countReady -ne ${#nodeTimePods[@]} && $countWait -le 10 ]]; do
        countReady=0
        for nodeIndex in ${!nodes[@]}; do
            if [[ -s $TEMPDIR/.get-k8s-info/nodesTimeReport/node$nodeIndex.out ]]; then
                countReady=$[ $countReady + 1 ]
            fi
        done
        countWait=$[ $countWait + 1 ]
        sleep 1
    done
    # Print report
    for nodeIndex in ${!nodes[@]}; do
        nodeDate=''
        if [[ -s $TEMPDIR/.get-k8s-info/nodesTimeReport/node$nodeIndex.out ]]; then
            nodeDate=$(cat $TEMPDIR/.get-k8s-info/nodesTimeReport/node$nodeIndex.out)
        else
            nodeDate='unavailable'
        fi
        echo -e "    - ${nodes[$nodeIndex]}\t$nodeDate" | tee -a $logfile
        echo -e "${nodes[$nodeIndex]}\t$nodeDate" >> $TEMPDIR/reports/nodes-time-report.txt
    done

    if [[ -s $TEMPDIR/.get-k8s-info/nodesTimeReport/jump.out ]]; then
        jumpDate=$(cat $TEMPDIR/.get-k8s-info/nodesTimeReport/jump.out)
    else
        jumpDate='unavailable'
    fi
    echo -e "\nJumpbox time: $jumpDate" >> $TEMPDIR/reports/nodes-time-report.txt
}
function performanceTasks {
    nodes=($($KUBECTLCMD get node -o name 2>> $logfile | cut -d '/' -f2))
    nodePerformancePods=()
    nodesPerformanceCommands=('getconf -a' 'top -bn 1 -w 512 | head -5' 'free -h' lscpu lsblk lsipc)
    nodesPerformanceFiles=('/proc/cpuinfo' '/proc/meminfo' '/proc/diskstats' '/proc/cmdline' '/proc/interrupts' '/proc/partitions')

    # Look for pods running on each node that have the performance command available
    for nodeIndex in ${!nodes[@]}; do
        for pod in $($KUBECTLCMD get pod --all-namespaces -o wide 2>> $logfile | grep " Running " | grep " ${nodes[$nodeIndex]} " | awk '{print $1"/"$2}'); do
            if $timeoutCmd 10 $KUBECTLCMD -n ${pod%%/*} exec ${pod#*/} -- type ${nodesPerformanceCommands[@]%% *} > /dev/null 2>&1; then
                nodePerformancePods[$nodeIndex]=$pod
                break
            fi
        done
    done

    # Collect performance details from the nodes
    for nodeIndex in ${!nodes[@]}; do
        nodePerformancePod=${nodePerformancePods[$nodeIndex]}
        if [[ ! -z $nodePerformancePod ]]; then
            mkdir -p $TEMPDIR/performance/nodes/${nodes[$nodeIndex]}/commands $TEMPDIR/performance/nodes/${nodes[$nodeIndex]}/proc
            for nodesPerformanceCommandIndex in ${!nodesPerformanceCommands[@]}; do
                createTask "$KUBECTLCMD -n ${nodePerformancePod%%/*} exec ${nodePerformancePod#*/} -- ${nodesPerformanceCommands[$nodesPerformanceCommandIndex]}" "$TEMPDIR/performance/nodes/${nodes[$nodeIndex]}/commands/${nodesPerformanceCommands[$nodesPerformanceCommandIndex]%% *}.txt"
            done
            for nodesPerformanceFile in ${nodesPerformanceFiles[@]}; do
                createTask "$KUBECTLCMD -n ${nodePerformancePod%%/*} exec ${nodePerformancePod#*/} -- cat ${nodesPerformanceFile}" "$TEMPDIR/performance/nodes/${nodes[$nodeIndex]}${nodesPerformanceFile}"
            done
        fi
    done
}

function captureCasLogs {
    namespace=$1
    casDefaultControllerPod=$2
    logFinished='false'
    echo "INFO: The sas-cas-server-default-controller from the $namespace namespace has recently started. Capturing logs on the background for up to 2 minutes..." | tee -a $logfile
    containerList=($($KUBECTLCMD -n $namespace get casdeployment default -o=jsonpath='{.spec.controllerTemplate.spec.initContainers[*].name} {.spec.controllerTemplate.spec.containers[*].name}' 2>> $logfile))
    podUid=$($KUBECTLCMD -n $namespace get pod $casDefaultControllerPod -o=jsonpath='{.metadata.uid}' 2>> $logfile)
    while [[ $logFinished != 'true' ]]; do
        newPodUid=$($KUBECTLCMD -n $namespace get pod $casDefaultControllerPod -o=jsonpath='{.metadata.uid}' 2>> $logfile)
        if [[ -z $newPodUid || $newPodUid != $podUid ]]; then
            echo "WARNING: The $casDefaultControllerPod pod crashed" | tee -a $logfile
            logFinished='true'
        else
            containerStatusList=($($KUBECTLCMD -n $namespace describe pod $casDefaultControllerPod 2>> $logfile | grep State | awk '{print $2}'))
            for containerIndex in ${!containerList[@]}; do
                if [[ ${containerStarted[$containerIndex]} -ne 1 && ${containerStatusList[$containerIndex]} != 'Waiting' ]]; then
                    echo "INFO: Capturing logs from the $casDefaultControllerPod:${containerList[$containerIndex]} container on the background" | tee -a $logfile
                    stdbuf -i0 -o0 -e0 $KUBECTLCMD -n $namespace logs $casDefaultControllerPod ${containerList[$containerIndex]} -f --tail=-1 > $TEMPDIR/kubernetes/$namespace/logs/${casDefaultControllerPod}_${containerList[$containerIndex]}.log 2>&1 &
                    logPid[$containerIndex]=$!
                    containerStarted[$containerIndex]=1
                fi
            done
            if [[ ! ${containerStatusList[@]} =~ 'Waiting' ]]; then
                logFinished='true'
                for pid in ${logPid[@]}; do
                    if [[ -d "/proc/$pid" ]]; then logFinished='false'; fi
                done
            fi
            currentTime=$(date +%s)
        fi
    done
}
function waitForCas {
    echo "WARNING: The sas-cas-server-default-controller pod isn't running. Waiting on the background for it to come up..." | tee -a $logfile
    currentTime=$(date +%s)
    targetTime=$[ $currentTime + 30 ]
    namespace=$1
    casDefaultControllerPod=$2
    while [[ -z $casDefaultControllerPod && $currentTime -lt $targetTime ]]; do
        casDefaultControllerPod=$($KUBECTLCMD -n $namespace get pod -l casoperator.sas.com/node-type=controller,casoperator.sas.com/server=default --no-headers 2>> $logfile | awk '{print $1}')
        currentTime=$(date +%s)
    done
    if [[ ! -z $casDefaultControllerPod ]]; then
        currentTime=$(date +%s)
        targetTime=$[ $currentTime + 120 ]
        captureCasLogs $namespace $casDefaultControllerPod &
        captureCasLogsPid=$!
        # Wait a few seconds before checking the subprocess directory
        sleep 5
        while [[ $currentTime -lt $targetTime && -d "/proc/$captureCasLogsPid" ]]; do
            sleep 1
            currentTime=$(date +%s)
        done
        jobs=$(ps -o pid= --ppid $captureCasLogsPid 2> /dev/null)
        if [[ ! -z $jobs || -d "/proc/$captureCasLogsPid" ]]; then
            echo "DEBUG: Killing log collector processes that were running on the background for namespace $namespace" >> $logfile
            kill $captureCasLogsPid > /dev/null 2>&1
            wait $captureCasLogsPid 2> /dev/null
            kill $jobs > /dev/null 2>&1
        fi
    else
        echo "WARNING: The sas-cas-server-default-controller did not start" | tee -a $logfile
    fi
}
function createTask() {
    echo $1\@$2 >> $TEMPDIR/.get-k8s-info/taskmanager/tasks
}
function runTask() {
    task=$1
    taskCommand=$(sed "$task!d" $TEMPDIR/.get-k8s-info/taskmanager/tasks | cut -d '@' -f1)
    taskOutput=$(sed "$task!d" $TEMPDIR/.get-k8s-info/taskmanager/tasks | cut -d '@' -f2)
    echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] [Task #$task] - Executing" >> $TEMPDIR/.get-k8s-info/workers/workers.log
    eval $timeoutCmd 300 ${taskCommand} > ${taskOutput} 2> $TEMPDIR/.get-k8s-info/workers/worker${worker}/syserr.log
    taskRc=$?
    if [[ $taskRc -eq 0 ]]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] [Task #$task] - Finished" >> $TEMPDIR/.get-k8s-info/workers/workers.log
    else
        if [[ $taskRc -eq 124 ]]; then
            echo "The task was terminated by get-k8s-info due to a timeout (5 minutes)" >> $TEMPDIR/.get-k8s-info/workers/worker${worker}/syserr.log
            echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] [Task #$task] - Finished (Timed Out)" >> $TEMPDIR/.get-k8s-info/workers/workers.log
            echo $task >> $TEMPDIR/.get-k8s-info/workers/worker${worker}/timedOutTasks
        else
            echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] [Task #$task] - Finished (With Errors)" >> $TEMPDIR/.get-k8s-info/workers/workers.log
        fi
        echo -e "\nTask #$task: $taskCommand > ${taskOutput}" | cat - $TEMPDIR/.get-k8s-info/workers/worker${worker}/syserr.log >> $TEMPDIR/.get-k8s-info/kubectl_errors.log
    fi
    echo $task >> $TEMPDIR/.get-k8s-info/workers/worker${worker}/completedTasks
}
function taskWorker() {
    worker=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] - Started" >> $TEMPDIR/.get-k8s-info/workers/workers.log
    currentTask=0
    lastTask=0

    mkdir $TEMPDIR/.get-k8s-info/workers/worker$worker
    touch $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks
    touch $TEMPDIR/.get-k8s-info/workers/worker${worker}/completedTasks
    touch $TEMPDIR/.get-k8s-info/workers/worker${worker}/timedOutTasks
    echo $BASHPID > $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid
    
    while true; do
        currentTask=$(tail -1 $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks)
        if [[ $currentTask -ne $lastTask && ! -z $currentTask ]]; then
            runTask $currentTask
            lastTask=$currentTask
        fi
        if [[ ! -f $TEMPDIR/.get-k8s-info/taskmanager/pid ]]; then
            echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] - Exiting (taskmanager was terminated)" >> $TEMPDIR/.get-k8s-info/workers/workers.log
            rm -f $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid
            exit 1
        fi
    done
}
function taskManager() {
    echo $BASHPID > $TEMPDIR/.get-k8s-info/taskmanager/pid

    workers=$1
    nextTask=1
    totalTasks=0
    endSignal=0
    workersStatus=()
    
    # Initialize control files
    touch $TEMPDIR/.get-k8s-info/taskmanager/tasks
    echo 0 > $TEMPDIR/.get-k8s-info/taskmanager/assigned
    echo 0 > $TEMPDIR/.get-k8s-info/taskmanager/completed
    echo 0 > $TEMPDIR/.get-k8s-info/taskmanager/total

    # Initialize workers
    for worker in $(seq 1 $workers); do
        workersStatus[$worker]='running'
        taskWorker $worker &
        while [[ ! -f "$TEMPDIR/.get-k8s-info/workers/worker$worker/pid" ]]; do
            sleep 0.1
        done
    done
    while true; do
        if [[ $endSignal -lt 2 ]]; then
            if [[ -f $TEMPDIR/.get-k8s-info/taskmanager/endsignal ]]; then endSignal=1; fi
            if [[ $endSignal -eq 0 ]]; then
                # Look for new tasks
                totalTasks=$(wc -l < $TEMPDIR/.get-k8s-info/taskmanager/tasks)
                echo $totalTasks > $TEMPDIR/.get-k8s-info/taskmanager/total
            else
                # Check for new tasks one last time
                newTotalTasks=$(wc -l < $TEMPDIR/.get-k8s-info/taskmanager/tasks)
                if [[ $newTotalTasks -eq $totalTasks ]]; then
                    endSignal=2
                else
                    totalTasks=$newTotalTasks
                    echo $totalTasks > $TEMPDIR/.get-k8s-info/taskmanager/total
                fi
            fi
        fi

        # Assign tasks to workers
        assignedTasks=0
        completedTasks=0
        for worker in $(seq 1 $workers); do
            workerAssignedTasks=$(wc -l < $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks)
            workerCompletedTasks=$(wc -l < $TEMPDIR/.get-k8s-info/workers/worker${worker}/completedTasks)
            if [[ $workerAssignedTasks -eq $workerCompletedTasks && $nextTask -le $totalTasks ]]; then
                echo $nextTask >> $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks
                nextTask=$[ $nextTask + 1 ]
                workerAssignedTasks=$[ $workerAssignedTasks + 1 ]
            fi
            assignedTasks=$[ $assignedTasks + $workerAssignedTasks ]
            completedTasks=$[ $completedTasks + $workerCompletedTasks ]
            if [[ $endSignal -eq 3 ]]; then
                if [[ -f $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid && $workerAssignedTasks -eq $workerCompletedTasks ]]; then
                    workerPid=$(cat $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid)
                    kill $workerPid > /dev/null 2>&1
                    rm -f $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid $TEMPDIR/.get-k8s-info/workers/worker${worker}/syserr.log
                    workersStatus[$worker]='idle'
                    echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] - Exiting (killed by taskmanager)" >> $TEMPDIR/.get-k8s-info/workers/workers.log
                fi
            fi
        done
        echo $assignedTasks > $TEMPDIR/.get-k8s-info/taskmanager/assigned
        echo $completedTasks > $TEMPDIR/.get-k8s-info/taskmanager/completed
        if [[ ! ${workersStatus[@]} =~ 'running' ]]; then
            rm -f $TEMPDIR/.get-k8s-info/taskmanager/pid
            exit 0
        fi
        if [[ $endSignal -eq 2 && $assignedTasks -eq $totalTasks ]]; then
            endSignal=3
        fi
        if [[ ! -f $TEMPDIR/.get-k8s-info/pid ]]; then
            exit 1
        fi
    done
}
function getNamespaceData() {
    for namespace in $@; do
        casDefaultControllerPod=''
        isViyaNs='false'
        waitForCasPid=''

        certmanagerobjects=(certificaterequests certificates issuers)
        crunchydata4objects=(pgclusters)
        crunchydata5objects=(pgupgrades postgresclusters)
        espobjects=(espconfigs esploadbalancers esprouters espservers espupdates)
        metricsobjects=(podmetrics)
        monitoringobjects=(alertmanagerconfigs alertmanagers podmonitors probes prometheusagents prometheuses prometheusrules scrapeconfigs servicemonitors thanosrulers)
        nginxobjects=(ingresses)
        openshiftobjects=(routes securitycontextconstraints)
        orchestrationobjects=(sasdeployments)
        viyaobjects=(casdeployments dataservers distributedredisclusters opendistroclusters)

        getobjects=(configmaps cronjobs daemonsets deployments endpoints events horizontalpodautoscalers jobs persistentvolumeclaims poddisruptionbudgets pods podtemplates replicasets rolebindings roles secrets serviceaccounts services statefulsets)
        describeobjects=(configmaps cronjobs daemonsets deployments endpoints horizontalpodautoscalers jobs persistentvolumeclaims poddisruptionbudgets pods podtemplates replicasets rolebindings roles secrets serviceaccounts services statefulsets)
        yamlobjects=(configmaps cronjobs daemonsets deployments endpoints horizontalpodautoscalers jobs persistentvolumeclaims poddisruptionbudgets pods podtemplates replicasets rolebindings roles serviceaccounts services statefulsets)
        jsonobjects=(configmaps cronjobs daemonsets deployments endpoints events horizontalpodautoscalers jobs persistentvolumeclaims poddisruptionbudgets pods podtemplates replicasets rolebindings roles serviceaccounts services statefulsets)

        if [[ $hasMonitoringCRD == 'true' ]]; then
            getobjects+=(${monitoringobjects[@]})
            describeobjects+=(${monitoringobjects[@]})
            yamlobjects+=(${monitoringobjects[@]})
            jsonobjects+=(${monitoringobjects[@]})
        fi
        if [[ $isOpenShift == 'true' ]]; then
            getobjects+=(${openshiftobjects[@]})
            describeobjects+=(${openshiftobjects[@]})
            yamlobjects+=(${openshiftobjects[@]})
            jsonobjects+=(${openshiftobjects[@]})
        else
            getobjects+=(${nginxobjects[@]})
            describeobjects+=(${nginxobjects[@]})
            yamlobjects+=(${nginxobjects[@]})
            jsonobjects+=(${nginxobjects[@]})
        fi
        if [[ $hasOrchestrationCRD == 'true' ]]; then
            getobjects+=(${orchestrationobjects[@]})
            describeobjects+=(${orchestrationobjects[@]})
            yamlobjects+=(${orchestrationobjects[@]})
            jsonobjects+=(${orchestrationobjects[@]})
        fi
        if [[ $hasMetricsServer == 'true' ]]; then
            getobjects+=(${metricsobjects[@]})
            describeobjects+=(${metricsobjects[@]})
            yamlobjects+=(${metricsobjects[@]})
            jsonobjects+=(${metricsobjects[@]})
        fi
        
        if [ ! -d $TEMPDIR/kubernetes/$namespace ]; then
            echo "  - Collecting information from the '$namespace' namespace" | tee -a $logfile
            mkdir -p $TEMPDIR/kubernetes/$namespace/describe $TEMPDIR/kubernetes/$namespace/get $TEMPDIR/kubernetes/$namespace/yaml $TEMPDIR/kubernetes/$namespace/json

            # If this namespace contains a Viya deployment
            if [[ " ${viyans[*]} " =~ " ${namespace} " ]]; then
                isViyaNs='true'

                getobjects+=(${viyaobjects[@]})
                describeobjects+=(${viyaobjects[@]})
                yamlobjects+=(${viyaobjects[@]})
                jsonobjects+=(${viyaobjects[@]})

                if [[ $hasCertManagerCRD == 'true' ]]; then
                    getobjects+=(${certmanagerobjects[@]})
                    describeobjects+=(${certmanagerobjects[@]})
                    yamlobjects+=(${certmanagerobjects[@]})
                    jsonobjects+=(${certmanagerobjects[@]})
                fi
                if [[ $hasCrunchyDataCRD != 'false' ]]; then
                    if [[ $hasCrunchyDataCRD == 'v5' ]]; then
                        getobjects+=(${crunchydata5objects[@]})
                        describeobjects+=(${crunchydata5objects[@]})
                        yamlobjects+=(${crunchydata5objects[@]})
                        jsonobjects+=(${crunchydata5objects[@]})
                    else
                        getobjects+=(${crunchydata4objects[@]})
                        describeobjects+=(${crunchydata4objects[@]})
                        yamlobjects+=(${crunchydata4objects[@]})
                        jsonobjects+=(${crunchydata4objects[@]})
                    fi
                fi
                if [[ $hasEspCRD == 'true' ]]; then
                    getobjects+=(${espobjects[@]})
                    describeobjects+=(${espobjects[@]})
                    yamlobjects+=(${espobjects[@]})
                    jsonobjects+=(${espobjects[@]})
                fi

                # Check if we should wait for cas logs
                casDefaultControllerPod=$($KUBECTLCMD -n $namespace get pod -l casoperator.sas.com/node-type=controller,casoperator.sas.com/server=default --no-headers 2>> $logfile | awk '{print $1}')
                if [[ (-z $casDefaultControllerPod || $($KUBECTLCMD -n $namespace get pod $casDefaultControllerPod --no-headers 2>> $logfile | awk '{print $5}' | grep -cE '^[0-9]+s$') -gt 0) ]]; then
                    waitForCasTimeout=$[ $(date +%s) + 120 ]
                    waitForCas $namespace $casDefaultControllerPod &
                    waitForCasPid=$!
                    echo $waitForCasPid:$waitForCasTimeout:$namespace >> $TEMPDIR/.get-k8s-info/waitForCas
                fi

                # performance debugtag
                if [[ "$PERFORMANCE" = true ]]; then
                    echo "    - Getting pods performance information" | tee -a $logfile
                    # Collect performance information related to specific pods
                    mkdir -p $TEMPDIR/performance/pods
                    podsPerformanceCommands=('df -hT' 'top -bn 1 -w 512' 'mount' 'ps -ef' 'sysctl -a' 'ulimit -a')
                    performancePods=()
                    
                    casPods=($($KUBECTLCMD -n $namespace get pod -l app.kubernetes.io/managed-by=sas-cas-operator --no-headers 2>> $logfile | awk '{print $1}'))
                    crunchyPods=($($KUBECTLCMD -n $namespace get pod -l "postgres-operator.crunchydata.com/data=postgres" --no-headers 2>> $logfile | awk '{print $1}'))
                    rabbitmqPods=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-rabbitmq-server' --no-headers 2>> $logfile | awk '{print $1}'))
                    opendistroPods=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-opendistro' --no-headers 2>> $logfile | awk '{print $1}'))
                    
                    riskPods=()
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-data-mining-risk-models' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-risk-cirrus-app' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-risk-cirrus-builder' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-risk-cirrus-core' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-risk-cirrus-objects' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app.kubernetes.io/name=sas-risk-cirrus-rcc' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-risk-data' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-risk-modeling-app' --no-headers 2>> $logfile | awk '{print $1}'))
                    riskPods+=($($KUBECTLCMD -n $namespace get pod -l 'app=sas-risk-modeling-core' --no-headers 2>> $logfile | awk '{print $1}'))
                    
                    computePods=()
                    runningPods=($($KUBECTLCMD -n $namespace get pods -o=jsonpath="{.items[?(@.status.phase=='Running')].metadata.name}" 2>> $logfile))
                    podTemplates=($($KUBECTLCMD -n $namespace get podtemplates --no-headers 2>> $logfile | awk '{print $1}'))
                    for podTemplate in ${podTemplates[@]}; do
                        podtemplatePods=($($KUBECTLCMD -n $namespace get pods -o=jsonpath="{.items[?(@.metadata.annotations.launcher\.sas\.com/pod-template-name=='$podTemplate')].metadata.name}" 2>> $logfile))
                        if [[ ! -z $podtemplatePods ]]; then
                            for pod in ${podtemplatePods[@]}; do
                                if [[ " ${runningPods[@]} " =~ " $pod " ]]; then
                                    computePods+=($pod)
                                    break
                                fi
                            done
                        fi
                    done
                    
                    performancePods+=(${casPods[@]} ${crunchyPods[@]} ${computePods[@]} ${opendistroPods[@]} ${rabbitmqPods[@]} ${riskPods[@]})
                    
                    if [[ ! -z $performancePods ]]; then
                        for performancePod in ${performancePods[@]}; do
                            mkdir -p $TEMPDIR/performance/pods/$performancePod/commands
                            for podsPerformanceCommandIndex in ${!podsPerformanceCommands[@]}; do
                                createTask "$KUBECTLCMD -n $namespace exec $performancePod -- ${podsPerformanceCommands[$podsPerformanceCommandIndex]}" "$TEMPDIR/performance/pods/$performancePod/commands/${podsPerformanceCommands[$podsPerformanceCommandIndex]%% *}.txt"
                            done
                        done
                    fi
                fi
                # backups debugtag
                if [[ "$BACKUPS" = true ]]; then
                    echo "    - Getting backups information" | tee -a $logfile
                    # Information from backup PVCs
                    for backupPod in $($KUBECTLCMD -n $namespace get pod -l 'sas.com/backup-job-type in (scheduled-backup,scheduled-backup-incremental,restore,purge-backup)' --no-headers 2>> $logfile | grep ' NotReady \| Running ' | awk '{print $1}'); do
                        # sas-common-backup-data PVC
                        podContainer=$($KUBECTLCMD -n $namespace get pod $backupPod -o jsonpath={.spec.containers[0].name} 2>> $logfile)
                        if $timeoutCmd 10 $KUBECTLCMD -n $namespace exec $backupPod -c $podContainer -- df -h /sasviyabackup 2>> $logfile > /dev/null; then
                            mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$backupPod
                            createTask "$KUBECTLCMD -n $namespace exec $backupPod -c $podContainer -- find /sasviyabackup -name status.json -exec echo '{}:' \; -exec cat {} \; -exec echo -e '\n' \;" "$TEMPDIR/kubernetes/$namespace/exec/$backupPod/${podContainer}_find_status.json.txt"
                            createTask "$KUBECTLCMD -n $namespace exec $backupPod -c $podContainer -- find /sasviyabackup -name *_pg_dump.log -exec echo '{}:' \; -exec cat {} \; -exec echo -e '\n' \;" "$TEMPDIR/kubernetes/$namespace/exec/$backupPod/${podContainer}_find_pg-dump.log.txt"
                            createTask "$KUBECTLCMD -n $namespace exec $backupPod -c $podContainer -- find /sasviyabackup -name pg_restore_*.log -exec echo '{}:' \; -exec cat {} \; -exec echo -e '\n' \;" "$TEMPDIR/kubernetes/$namespace/exec/$backupPod/${podContainer}_find_pg-restore.log.txt"
                            createTask "$KUBECTLCMD -n $namespace exec $backupPod -c $podContainer -- bash -c 'ls -lRa /sasviyabackup'" "$TEMPDIR/kubernetes/$namespace/exec/$backupPod/${podContainer}_ls_sasviyabackup.txt"
                            break
                        fi
                    done
                    # sas-cas-backup-data PVC
                    if [[ ! -z $casDefaultControllerPod ]]; then
                        mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$casDefaultControllerPod
                        createTask "$KUBECTLCMD -n $namespace exec $casDefaultControllerPod -c sas-backup-agent -- bash -c 'ls -lRa /sasviyabackup'" "$TEMPDIR/kubernetes/$namespace/exec/$casDefaultControllerPod/sas-backup-agent_ls_sasviyabackups.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $casDefaultControllerPod -c sas-backup-agent -- find /sasviyabackup -name status.json -exec echo '{}:' \; -exec cat {} \; -exec echo -e '\n' \;" "$TEMPDIR/kubernetes/$namespace/exec/$casDefaultControllerPod/sas-backup-agent_find_status.json.txt"
                    fi
                    # Past backup and restore status
                    createTask "$KUBECTLCMD -n $namespace get jobs -l 'sas.com/backup-job-type in (scheduled-backup, scheduled-backup-incremental)' -L 'sas.com/sas-backup-id,sas.com/backup-job-type,sas.com/sas-backup-job-status,sas.com/sas-backup-persistence-status,sas.com/sas-backup-datasource-types,sas.com/sas-backup-include-postgres' --sort-by=.status.startTime" "$TEMPDIR/reports/backup-status_$namespace.txt"
                    createTask "$KUBECTLCMD -n $namespace get jobs -l 'sas.com/backup-job-type=restore' -L 'sas.com/sas-backup-id,sas.com/backup-job-type,sas.com/sas-restore-id,sas.com/sas-restore-status,sas.com/sas-restore-tenant-status-provider'" "$TEMPDIR/reports/restore-status_$namespace.txt"
                fi
                
                # If using Cert-Manager
                if [[ "$($KUBECTLCMD -n $namespace get $($KUBECTLCMD -n $namespace get cm -o name 2>> $logfile| grep sas-certframe-user-config | tail -1) -o=jsonpath='{.data.SAS_CERTIFICATE_GENERATOR}' 2>> $logfile)" == 'cert-manager' && "${#certmgrns[@]}" -eq 0 ]]; then 
                    echo "WARNING: cert-manager configured to be used by Viya in namespace $namespace, but a cert-manager instance wasn't found in the kubernetes cluster." | tee -a $logfile
                fi

                echo "    - Getting order number" | tee -a $logfile
                createTask "$KUBECTLCMD -n $namespace get secret -l 'orchestration.sas.com/lifecycle=image' -o jsonpath={.items[0].data.username} 2>> $logfile | base64 -d" "$TEMPDIR/versions/${namespace}_order.txt"

                echo "    - Getting cadence information" | tee -a $logfile
                createTask "$KUBECTLCMD -n $namespace get $($KUBECTLCMD get cm -n $namespace -o name 2>> $logfile | grep sas-deployment-metadata) -o jsonpath='VERSION {.data.SAS_CADENCE_DISPLAY_NAME}   RELEASE {.data.SAS_CADENCE_RELEASE}'" "$TEMPDIR/versions/${namespace}_cadence.txt"

                echo "    - Getting license information" | tee -a $logfile
                createTask "$KUBECTLCMD -n $namespace get $($KUBECTLCMD get secret -n $namespace -o name 2>> $logfile | grep sas-license) -o jsonpath='{.data.SAS_LICENSE}' | base64 -d 2>> $logfile | cut -d '.' -f2 | base64 -d" "$TEMPDIR/versions/${namespace}_license.txt"

                # config debugtag
                if [[ "$CONFIG" = true ]]; then
                    echo "    - Running sas-bootstrap-config kv read" | tee -a $logfile
                    for consulPod in $($KUBECTLCMD -n $namespace get pod -l 'app=sas-consul-server' --no-headers 2>> $logfile | awk '{print $1}'); do
                        mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$consulPod
                        createTask "$KUBECTLCMD -n $namespace exec $consulPod -c sas-consul-server -- bash -c 'export CONSUL_HTTP_ADDR=\$SAS_URL_SERVICE_SCHEME://localhost:8500;consul kv get --recurse locks'" "$TEMPDIR/kubernetes/$namespace/exec/$consulPod/sas-consul-server_consul_kv_get_--recurse_locks.txt"
                        $KUBECTLCMD -n $namespace exec $consulPod -c sas-consul-server -- bash -c "export CONSUL_HTTP_ADDR=\$SAS_URL_SERVICE_SCHEME://localhost:8500;/opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse" > $TEMPDIR/kubernetes/$namespace/exec/$consulPod/sas-consul-server_sas-bootstrap-config_kv_read.txt 2>> $logfile
                        if [ $? -eq 0 ]; then 
                            removeSensitiveData $TEMPDIR/kubernetes/$namespace/exec/$consulPod/sas-consul-server_sas-bootstrap-config_kv_read.txt
                            break
                        fi
                    done
                fi
                # postgres debugtag
                if [[ "$POSTGRES" = true && "$hasCrunchyDataCRD" != 'false' ]]; then
                    echo "    - Getting Crunchy Data PostgreSQL information" | tee -a $logfile
                    if [ $hasCrunchyDataCRD == 'v4' ]; then
                        #Crunchy4 commands
                        for pgcluster in $($KUBECTLCMD -n $namespace get pgclusters --no-headers 2>> $logfile | awk '{print $1}'); do
                            if [[ $pgcluster =~ 'crunchy' ]]; then 
                                for crunchyPod in $($KUBECTLCMD -n $namespace get pod -l "crunchy-pgha-scope=$pgcluster,role" --no-headers 2>> $logfile | awk '{print $1}'); do
                                    mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$crunchyPod
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- patronictl list" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_patronictl_list.txt"
                                done
                            fi
                        done
                    fi
                    if [ $hasCrunchyDataCRD == 'v5' ]; then
                        #Crunchy5 commands
                        for pgcluster in $($KUBECTLCMD -n $namespace get postgresclusters.postgres-operator.crunchydata.com --no-headers 2>> $logfile | awk '{print $1}'); do
                            if [[ $pgcluster =~ 'crunchy' ]]; then
                                crunchyPods=($($KUBECTLCMD -n $namespace get pod -l "postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$pgcluster" --no-headers 2>> $logfile | awk '{print $1}'))
                                if [[ -z $crunchyPods ]]; then
                                    crunchyPods=($($KUBECTLCMD -n $namespace get pod -l "postgres-operator.crunchydata.com/data=postgres,postgres-operator.crunchydata.com/cluster=$pgcluster" --no-headers 2>> $logfile | awk '{print $1}'))
                                fi
                                for crunchyPod in ${crunchyPods[@]}; do
                                    mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$crunchyPod
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- psql -d SharedServices -c 'SELECT now() - pg_stat_activity.query_start AS duration,* FROM pg_stat_activity ORDER BY duration desc;'" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_psql_running-queries.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- patronictl list" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_patronictl_list.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- patronictl history" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_patronictl_history.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- patronictl show-config" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_patronictl_show-config.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- bash -c 'cat \$PGDATA/postgresql.conf'" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_cat_postgresql.conf.txt" 
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- psql -d SharedServices -c 'SELECT n_live_tup as Estimated_Rows,* FROM pg_stat_user_tables ORDER BY n_live_tup desc;'" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_psql_table-statistics.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- psql -d SharedServices -c 'SELECT datname Database_Name, usename, application_name, COUNT(*) Count_By_Apps,version SSL_Version FROM pg_stat_activity a, pg_stat_ssl s where a.pid = s.pid GROUP BY datname,usename,application_name,version ORDER BY 1,4;'" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_psql_application-connections.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- psql -d SharedServices -c 'SELECT datname AS database_name, pg_size_pretty(pg_database_size(datname)) AS database_size FROM pg_database;'" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_psql_database-sizes.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- psql -d SharedServices -c \"SELECT nspname || '.' || relname AS relation, pg_size_pretty(pg_total_relation_size(C.oid)) AS Total_Size FROM pg_class C JOIN pg_namespace N ON N.oid = C.relnamespace WHERE relkind = 'r' AND nspname = 'pg_catalog' AND relname = 'pg_largeobject' ORDER BY pg_total_relation_size(C.oid) DESC;\"" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_psql_largeobject-table-size.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- psql -d SharedServices -c \"SELECT schemaname || '.' || relname AS relation, pg_size_pretty(pg_total_relation_size(relid)) As Total_Size, pg_size_pretty(pg_indexes_size(relid)) as Index_Size, pg_size_pretty(pg_relation_size(relid)) as Actual_Size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;\"" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_psql_table-sizes.txt"
                                    createTask "$KUBECTLCMD -n $namespace exec -i $crunchyPod -c database -- vacuumlo -n -h ${pgcluster}-ha -U dbmsowner -v SharedServices <<< \$($KUBECTLCMD -n $namespace get secret ${pgcluster}-pguser-dbmsowner -o jsonpath={.data.password} | base64 -d)" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_vacuumlo_dry-run.txt"
                                done
                                mkdir -p $TEMPDIR/kubernetes/$namespace/exec/${pgcluster}-repo-host-0
                                createTask "$KUBECTLCMD -n $namespace exec ${pgcluster}-repo-host-0 -c pgbackrest -- pgbackrest info" "$TEMPDIR/kubernetes/$namespace/exec/${pgcluster}-repo-host-0/pgbackrest_pgbackrest_info.txt"
                                createTask "$KUBECTLCMD -n $namespace exec ${pgcluster}-repo-host-0 -c pgbackrest -- pgbackrest check --stanza=db --log-level-console=debug" "$TEMPDIR/kubernetes/$namespace/exec/${pgcluster}-repo-host-0/pgbackrest_pgbackrest_check.txt"
                            fi
                        done
                    fi
                fi
                # rabbitmq debugtag
                if [[ "$RABBITMQ" = true ]]; then
                    echo "    - Getting RabbitMQ information" | tee -a $logfile
                    for rabbitmqPod in $($KUBECTLCMD -n $namespace get pod -l 'app=sas-rabbitmq-server' --no-headers 2>> $logfile | awk '{print $1}'); do
                        mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl status'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_status.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl cluster_status'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_cluster-status.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl environment'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_environment.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_connections pid name port host peer_port peer_host ssl ssl_protocol ssl_key_exchange ssl_cipher ssl_hash peer_cert_subject peer_cert_issuer peer_cert_validity state channels protocol auth_mechanism user vhost timeout frame_max channel_max client_properties recv_oct recv_cnt send_oct send_cnt send_pend connected_at'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list_connections.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_channels pid connection name number user vhost transactional confirm consumer_count messages_unacknowledged messages_uncommitted acks_uncommitted messages_unconfirmed prefetch_count global_prefetch_count'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list_channels.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmq-diagnostics command_line_arguments'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmq-diagnostics_command-line-arguments.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmq-diagnostics os_env'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmq-diagnostics_os-env.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_queues name durable auto_delete arguments policy operator_policy effective_policy_definition pid owner_pid exclusive exclusive_consumer_pid exclusive_consumer_tag messages_ready messages_unacknowledged messages messages_ready_ram messages_unacknowledged_ram messages_ram messages_persistent message_bytes message_bytes_ready message_bytes_unacknowledged message_bytes_ram message_bytes_persistent head_message_timestamp disk_reads disk_writes consumers consumer_utilisation consumer_capacity memory slave_pids synchronised_slave_pids state type leader members online slave_pids synchronised_slave_pids'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-queues.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_queues messages_ready consumers name | grep -v ^0 | (sed -u 3q; sort -r -n -k 1)'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-queues-nonempty.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_exchanges name type durable auto_delete internal arguments policy'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-exchanges.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_bindings'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-bindings.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_consumers'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list_consumers.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_permissions'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-permissions.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_policies'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-policies.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_global_parameters'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-global-parameters.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_parameters'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-parameters.txt"
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl list_unresponsive_queues'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_list-unresponsive-queues.txt"
                    done
                fi
                # opensearch debugtag
                if [[ "$OPENSEARCH" = true ]]; then
                    echo "    - Getting OpenSearch information" | tee -a $logfile
                    opendistroToken=$(echo -n $($KUBECTLCMD -n $namespace get secret sas-opendistro-sasadmin-secret -o jsonpath='{.data.username}' 2>> $logfile | base64 -d 2>> $logfile):$($KUBECTLCMD -n $namespace get secret sas-opendistro-sasadmin-secret -o jsonpath='{.data.password}' 2>> $logfile | base64 -d 2>> $logfile) | base64 2>> $logfile)
                    opendistroClientCm=($($KUBECTLCMD get cm -n $namespace -o custom-columns=CREATED:.metadata.creationTimestamp,NAME:.metadata.name 2>> $logfile | grep ' sas-opendistro-client-config-' | sort -k1 -t ' ' -r | awk '{print $2}'))
                    if [[ ! -z $opendistroClientCm ]]; then
                        if [[ $($KUBECTLCMD -n $namespace get cm ${opendistroClientCm[0]} -o jsonpath='{.data.OPENSEARCH_CLIENT_SSL_ENABLED}' 2>> $logfile) == 'true' ]]; then
                            opendistroProtocol='https'
                        else
                            opendistroProtocol='http'
                        fi

                        for opendistroPod in $($KUBECTLCMD -n $namespace get pod -l 'sas.com/master-role=true' --no-headers 2>> $logfile | awk '{print $1}'); do
                            mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$opendistroPod
                            createTask "$KUBECTLCMD -n $namespace exec $opendistroPod -c sas-opendistro -- curl -sk --url $opendistroProtocol://localhost:9200/_cluster/health?pretty=true --header 'Authorization: Basic $opendistroToken'" "$TEMPDIR/kubernetes/$namespace/exec/$opendistroPod/sas-opendistro_cluster_health.txt"
                            createTask "$KUBECTLCMD -n $namespace exec $opendistroPod -c sas-opendistro -- curl -sk --url $opendistroProtocol://localhost:9200/_cat/indices?s=index --header 'Authorization: Basic $opendistroToken'" "$TEMPDIR/kubernetes/$namespace/exec/$opendistroPod/sas-opendistro_cat_indices.txt"
                            createTask "$KUBECTLCMD -n $namespace exec $opendistroPod -c sas-opendistro -- curl -sk --url $opendistroProtocol://localhost:9200/_cat/shards  --header 'Authorization: Basic $opendistroToken'" "$TEMPDIR/kubernetes/$namespace/exec/$opendistroPod/sas-opendistro_cat_shards.txt"
                        done
                    fi
                fi
            fi
            # Collect logs
            podList=$($KUBECTLCMD -n $namespace get pod --no-headers 2>> $logfile | awk '{print $1}')
            if [ ! -z "$podList" ]; then
                echo "    - kubectl logs" | tee -a $logfile
                mkdir -p $TEMPDIR/kubernetes/$namespace/logs/previous
                restartedPodList=$($KUBECTLCMD -n $namespace get pod --no-headers 2>> $logfile | awk '{if ($4 > 0) print $1}' | tr '\n' ' ')
                for pod in ${podList[@]}; do 
                    echo "      - $pod" | tee -a $logfile
                    if [[ $isViyaNs == 'false' || -z $waitForCasPid || $pod != 'sas-cas-server-default-controller' ]]; then
                        for container in $($KUBECTLCMD -n $namespace get pod $pod -o=jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}' 2>> $logfile); do 
                            createTask "$KUBECTLCMD -n $namespace logs $pod $container" "$TEMPDIR/kubernetes/$namespace/logs/${pod}_$container.log"
                            if [[ " ${restartedPodList[@]} " =~ " $pod " ]]; then
                                createTask "$KUBECTLCMD -n $namespace logs $pod $container --previous" "$TEMPDIR/kubernetes/$namespace/logs/previous/${pod}_${container}_previous.log"
                            fi
                        done
                    else
                        echo "INFO: Logs from the sas-cas-server-default-controller pod are being collected through a background process." | tee -a $logfile
                    fi
                done
            fi

            # get objects
            echo "    - kubectl get" | tee -a $logfile
            for object in ${getobjects[@]}; do
                echo "      - $object" | tee -a $logfile
                createTask "$KUBECTLCMD -n $namespace get $object -o wide" "$TEMPDIR/kubernetes/$namespace/get/$object.txt"
            done
            # describe objects
            echo "    - kubectl describe" | tee -a $logfile
            for object in ${describeobjects[@]}; do
                echo "      - $object" | tee -a $logfile
                if [[ $object == 'sasdeployments' && $isViyaNs == 'true' ]]; then 
                    $KUBECTLCMD -n $namespace describe $object > $TEMPDIR/kubernetes/$namespace/describe/$object.txt 2>&1
                    if [[ $? -ne 0 ]]; then 
                        cat $TEMPDIR/kubernetes/$namespace/describe/$object.txt >> $logfile
                    else
                        removeSensitiveData $TEMPDIR/kubernetes/$namespace/describe/$object.txt
                    fi
                else 
                    createTask "$KUBECTLCMD -n $namespace describe $object" "$TEMPDIR/kubernetes/$namespace/describe/$object.txt"
                fi
            done
            # yaml objects
            echo "    - kubectl get -o yaml" | tee -a $logfile
            for object in ${yamlobjects[@]}; do
                echo "      - $object" | tee -a $logfile
                if [[ $object == 'sasdeployments' && $isViyaNs == 'true' ]]; then
                    $KUBECTLCMD -n $namespace get $object -o yaml > $TEMPDIR/kubernetes/$namespace/yaml/$object.yaml 2>&1
                    if [[ $? -ne 0 ]]; then 
                        cat $TEMPDIR/kubernetes/$namespace/yaml/$object.yaml >> $logfile
                        echo -n '' > $TEMPDIR/kubernetes/$namespace/yaml/$object.yaml
                    else
                        removeSensitiveData $TEMPDIR/kubernetes/$namespace/yaml/$object.yaml
                    fi
                else
                    createTask "$KUBECTLCMD -n $namespace get $object -o yaml" "$TEMPDIR/kubernetes/$namespace/yaml/$object.yaml"
                fi
            done
            # json objects
            echo "    - kubectl get -o json" | tee -a $logfile
            for object in ${jsonobjects[@]}; do
                echo "      - $object" | tee -a $logfile
                if [[ $object == 'sasdeployments' && $isViyaNs == 'true' ]]; then
                    $KUBECTLCMD -n $namespace get $object -o json > $TEMPDIR/kubernetes/$namespace/json/$object.json 2>&1
                    if [[ $? -ne 0 ]]; then 
                        cat $TEMPDIR/kubernetes/$namespace/json/$object.json >> $logfile
                        echo -n '' > $TEMPDIR/kubernetes/$namespace/json/$object.json
                    else
                        removeSensitiveData $TEMPDIR/kubernetes/$namespace/json/$object.json
                    fi
                else
                    createTask "$KUBECTLCMD -n $namespace get $object -o json" "$TEMPDIR/kubernetes/$namespace/json/$object.json"
                fi
            done
            # kubectl top pods
            echo "    - kubectl top pod" | tee -a $logfile
            mkdir -p $TEMPDIR/kubernetes/$namespace/top
            if [[ $KUBECTLCMD == 'kubectl' ]]; then
                createTask "$KUBECTLCMD -n $namespace top pod" "$TEMPDIR/kubernetes/$namespace/top/pods.txt"
            else
                createTask "$KUBECTLCMD -n $namespace adm top pod" "$TEMPDIR/kubernetes/$namespace/top/pods.txt"
            fi
            unset podList
        fi
    done
}
function generateKviyaReport() {
    namespace=$1
    # Collect 'kviya' compatible playback file
    saveTime=$(date +"%YD%mD%d_%HT%MT%S")
    mkdir -p $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime
    cp $TEMPDIR/kubernetes/clusterwide/get/nodes.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/getnodes.out 2>> $logfile
    cp $TEMPDIR/kubernetes/clusterwide/describe/nodes.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/nodes-describe.out 2>> $logfile
    cp $TEMPDIR/kubernetes/$namespace/get/pods.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/getpod.out 2>> $logfile
    cp $TEMPDIR/kubernetes/$namespace/get/events.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/podevents.out 2>> $logfile
    cp $TEMPDIR/kubernetes/clusterwide/top/nodes.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/nodesTop.out 2>> $logfile
    cp $TEMPDIR/kubernetes/$namespace/top/pods.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/podsTop.out 2>> $logfile
    if [[ " ${viyans[@]} " =~ " $namespace " ]]; then
        # Capture environment details
        environmentDetails $namespace > $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/environmentDetails.out
        if [[ ! -f $TEMPDIR/.get-k8s-info/sendToCase.out ]]; then
            cp $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/environmentDetails.out $TEMPDIR/.get-k8s-info/sendToCase.out
        else
            grep -A30 '^Viya Environment$' $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/environmentDetails.out >> $TEMPDIR/.get-k8s-info/sendToCase.out
        fi
        # Generate kviya report
        echo "DEBUG: Generating kviya report for namespace $namespace" >> $logfile
        kviyaReport $namespace
    fi
    tar -czf $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime.tgz --directory=$TEMPDIR/kubernetes/$namespace/.kviya $saveTime 2>> $logfile
    rm -rf $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime 2>> $logfile
}
function showProgress {
    percent=$[ 100 * $completedTasks / $totalTasks ]
    done=$[ 40 * $percent / 100 ]
    todo=$[ 40 - $done ]

    done_sub_bar=$(printf "%${done}s" | tr " " "#")
    todo_sub_bar=$(printf "%${todo}s" | tr " " "-")

    echo -ne "Progress: ${loading[$loadingIndex]} [$done_sub_bar$todo_sub_bar] $percent% ($completedTasks/$totalTasks) Tasks Completed"
}
function waitForTasks {
    touch $TEMPDIR/.get-k8s-info/taskmanager/endsignal

    loading=('/' '-' '\' '|')
    loadingIndex=0

    completedTasks=0
    totalTasks=0

    seperator='---------------------------------------------------------------------------------------------------'
    rows="%6s  %5s  %7s    %s\n"

    echo -e '\nWaiting for tasks to finish:\n'
    for n in $(seq -3 $WORKERS); do
        echo;
    done
    while [[ $completedTasks -lt $totalTasks || $totalTasks -eq 0 ]]; do
        newCompletedTasks=$(cat $TEMPDIR/.get-k8s-info/taskmanager/completed)
        if [[ ! -z $newCompletedTasks ]]; then
            newTotalTasks=$(cat $TEMPDIR/.get-k8s-info/taskmanager/total)
            if [[ ! -z $newTotalTasks ]]; then 
                completedTasks=$newCompletedTasks
                totalTasks=$newTotalTasks
            fi
        fi

        if [[ -f $TEMPDIR/.get-k8s-info/taskmanager/pid ]]; then
            tput cup $[ $(tput lines) - $WORKERS - 5 ] 0
            showProgress
            printf "\n\n$rows" Worker Task Time Command
            printf "%.$(tput cols)s\n" "$seperator"
            
            for worker in $(seq 1 $WORKERS); do
                workerStatus[${worker}0]=$(tail -1 $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks)
                completedTask=$(tail -1 $TEMPDIR/.get-k8s-info/workers/worker${worker}/completedTasks)
                if [[ $completedTask -ne ${workerStatus[${worker}0]} ]]; then
                    taskStart=$(date -r $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks +%s)
                    workerStatus[${worker}1]=$(date -ud "@$[ $(date +%s) - $taskStart ]" +%M:%S)
                    workerStatus[${worker}2]=$(sed "${workerStatus[${worker}0]}!d" $TEMPDIR/.get-k8s-info/taskmanager/tasks | cut -d '@' -f1)
                    if [[ ${#workerStatus[${worker}2]} -gt 100 ]]; then
                        workerStatus[${worker}2]="${workerStatus[${worker}2]::100} ..."
                    fi
                else
                    if [[ ! -f $TEMPDIR/.get-k8s-info/workers/worker${worker}/pid ]]; then
                        workerStatus[${worker}2]='Finished'
                    fi
                fi
                if [[ ${workerStatus[${worker}0]} != ${lastWorkerStatus[${worker}0]} ||
                      ${workerStatus[${worker}1]} != ${lastWorkerStatus[${worker}1]} ||
                      ${workerStatus[${worker}2]} != ${lastWorkerStatus[${worker}2]} ]]; then
                    tput cup $[ $(tput lines) - $WORKERS + $worker -2 ] 0
                    tput el
                    if [[ ${workerStatus[${worker}2]} == 'Finished' ]]; then
                        printf "$rows" "$worker" " " " " "${workerStatus[${worker}2]}"
                    else
                        printf "$rows" "$worker" "${workerStatus[${worker}0]}" "${workerStatus[${worker}1]}" "${workerStatus[${worker}2]}"
                    fi
                fi
                lastWorkerStatus[${worker}0]=${workerStatus[${worker}0]}
                lastWorkerStatus[${worker}1]=${workerStatus[${worker}1]}
                lastWorkerStatus[${worker}2]=${workerStatus[${worker}2]}
            done
        else
            completedTasks=$(cat $TEMPDIR/.get-k8s-info/taskmanager/completed)
            tput cup $[ $(tput lines) - $WORKERS - 5 ] 0
            showProgress
            tput ed
            break
        fi
        if [[ $loadingIndex -eq 3 ]]; then loadingIndex=0; else loadingIndex=$[ $loadingIndex + 1 ]; fi
        sleep 0.1s
    done
    echo;
    # Remove sensitive data from get-k8s-info files
    removeSensitiveData $TEMPDIR/.get-k8s-info/kubectl_errors.log
    removeSensitiveData $TEMPDIR/.get-k8s-info/taskmanager/tasks

    for worker in $(seq 1 $WORKERS); do
        timedOutTasks+=($(cat $TEMPDIR/.get-k8s-info/workers/worker${worker}/timedOutTasks))
    done
    if [[ ${#timedOutTasks[@]} -gt 0 ]]; then
        IFS=$'\n' timedOutTasks=($(sort -n <<<"${timedOutTasks[*]}"))
        unset IFS
        echo -e '\nWARNING: The following tasks were terminated by get-k8s-info due to a timeout (5 minutes):' | tee -a $logfile
        printf "\n%5s    %s\n" Task Command | tee -a $logfile
        echo $seperator | tee -a $logfile
        for task in ${timedOutTasks[@]}; do
            taskCommand=$(sed "$task!d" $TEMPDIR/.get-k8s-info/taskmanager/tasks | cut -d '@' -f1)
            if [[ ${#taskCommand} -gt 100 ]]; then
                taskCommand="${taskCommand::100} ..."
            fi
            printf "%5s    %s\n" "${task}" "${taskCommand}" | tee -a $logfile
        done
    fi

    if [[ -f $TEMPDIR/.get-k8s-info/waitForCas ]]; then
        for line in $(cat $TEMPDIR/.get-k8s-info/waitForCas); do
            waitForCasPid=$(cut -d ':' -f1 <<< $line)
            waitForCasTimeout=$(cut -d ':' -f2 <<< $line)
            waitForCasNamespace=$(cut -d ':' -f3 <<< $line)
            currentTime=$[ $(date +%s) - 30 ]
            if [[ $currentTime -lt $waitForCasTimeout ]]; then
                echo -e "\nINFO: Waiting $[ $waitForCasTimeout - $currentTime ] seconds for background processes from namespace $waitForCasNamespace to finish"
                sleep $[ $waitForCasTimeout - $currentTime ]
            fi
            captureCasLogsPid=$(ps -o pid= --ppid "$waitForCasPid")
            if [[ ! -z $captureCasLogsPid && -d /proc/$captureCasLogsPid ]]; then
                jobs=$(ps -o pid= --ppid "$captureCasLogsPid")
                kill $captureCasLogsPid > /dev/null 2>&1
                wait $captureCasLogsPid 2> /dev/null
                kill $jobs > /dev/null 2>&1
            fi
            kill $waitForCasPid > /dev/null 2>&1
            wait $waitForCasPid 2> /dev/null
        done
    fi
}
tput civis
tput rmam
TEMPDIR=$(mktemp -d --tmpdir=$OUTPATH -t .get-k8s-info.tmp.XXXXXXXXXX 2> /dev/null)
mkdir -p $TEMPDIR/.get-k8s-info/workers $TEMPDIR/.get-k8s-info/taskmanager $TEMPDIR/reports $TEMPDIR/versions
echo $BASHPID > $TEMPDIR/.get-k8s-info/pid

# Launch workers
taskManager $WORKERS &

echo -e "\nINFO: Capturing environment information...\n" | tee -a $logfile

# Look for ingress-nginx namespaces
echo 'DEBUG: Looking for Ingress Controller namespaces' >> $logfile
ingressns=($($KUBECTLCMD get deploy -l 'app.kubernetes.io/name=ingress-nginx' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq ))
if [[ $isOpenShift == 'true' ]]; then
    ingressns+=($($KUBECTLCMD get deploy -l 'ingresscontroller.operator.openshift.io/owning-ingresscontroller' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq ))
fi
if [ ${#ingressns[@]} -gt 0 ]; then
    if [ ${#ingressns[@]} -gt 1 ]; then
        echo "WARNING: Multiple Ingress Controller instances were found in the current kubernetes cluster." | tee -a $logfile
    fi
    for INGRESS_NS in ${ingressns[@]}; do
        echo INGRESS_NS: $INGRESS_NS >> $logfile
        echo "  - Ingress controller version" | tee -a $logfile
        createTask "$KUBECTLCMD -n $INGRESS_NS get deploy -l 'app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller' -o jsonpath='{.items[0].spec.template.spec.containers[].image}'" "$TEMPDIR/versions/${INGRESS_NS}_ingress-controller-version.txt"
    done
    namespaces+=(${ingressns[@]})
else
    echo "WARNING: An Ingress Controller instance wasn't found in the current kubernetes cluster." | tee -a $logfile
    echo "WARNING: The script will continue without collecting nginx information." | tee -a $logfile
fi
# Look for cert-manager namespaces
echo 'DEBUG: Looking for cert-manager namespaces' >> $logfile
certmgrns=($($KUBECTLCMD get deploy -l 'app.kubernetes.io/name=cert-manager' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [ ${#certmgrns[@]} -gt 0 ]; then
    if [ ${#certmgrns[@]} -gt 1 ]; then
        echo "WARNING: Multiple instances of cert-manager were detected in the kubernetes cluster." | tee -a $logfile
    fi
    for CERTMGR_NS in ${certmgrns[@]}; do
        echo -e "CERTMGR_NS: $CERTMGR_NS" >> $logfile
        echo "  - cert-manager version" | tee -a $logfile
        createTask "$KUBECTLCMD -n $CERTMGR_NS get deploy -l 'app.kubernetes.io/name=cert-manager,app.kubernetes.io/component=controller' -o jsonpath='{.items[0].spec.template.spec.containers[].image}'" "$TEMPDIR/versions/${CERTMGR_NS}_cert-manager-version.txt"
    done
    namespaces+=(${certmgrns[@]})
fi
# Look for OCP cert-utils-operator namespaces
if [[ $isOpenShift == 'true' ]]; then
    echo 'DEBUG: Looking for OCP cert-utils-operator namespaces' >> $logfile
    ocpcertutilsns=($($KUBECTLCMD get deploy --all-namespaces 2>> $logfile | grep cert-utils-operator-controller-manager | awk '{print $1}' | sort | uniq))
    if [ ${#ocpcertutilsns[@]} -gt 0 ]; then
        if [ ${#ocpcertutilsns[@]} -gt 1 ]; then
            echo "WARNING: Multiple instances of OCP cert-utils-operator were detected in the kubernetes cluster." | tee -a $logfile
        fi
        for OCPCERTUTILS_NS in ${ocpcertutilsns[@]}; do
            echo -e "OCPCERTUTILS_NS: $OCPCERTUTILS_NS" >> $logfile
            echo "  - cert-utils-operator version" | tee -a $logfile
            createTask "$KUBECTLCMD -n $OCPCERTUTILS_NS get deploy cert-utils-operator-controller-manager -o jsonpath='{.spec.template.spec.containers[].image}'" "$TEMPDIR/versions/${OCPCERTUTILS_NS}_ocp-cert-utils-operator-version.txt"
        done
        namespaces+=(${ocpcertutilsns[@]})
    fi
fi
# Look for NFS External Provisioner namespaces
echo 'DEBUG: Looking for NFS External Provisioner namespaces' >> $logfile
nfsprovisionerns=($($KUBECTLCMD get deploy -l 'app=nfs-subdir-external-provisioner' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [ ${#nfsprovisionerns[@]} -gt 0 ]; then
    if [ ${#nfsprovisionerns[@]} -gt 1 ]; then
        echo "WARNING: Multiple instances of the NFS External Provisioner were detected in the kubernetes cluster." | tee -a $logfile
    fi
    for NFSPROVISIONER_NS in ${nfsprovisionerns[@]}; do
        echo -e "NFSPROVISIONER_NS: $NFSPROVISIONER_NS" >> $logfile
        echo "  - NFS External Provisioner version" | tee -a $logfile
        createTask "$KUBECTLCMD -n $NFSPROVISIONER_NS get deploy -l 'app=nfs-subdir-external-provisioner' -o jsonpath='{.items[0].spec.template.spec.containers[].image}'" "$TEMPDIR/versions/${NFSPROVISIONER_NS}_nfs-provisioner-version.txt"
    done
    namespaces+=(${nfsprovisionerns[@]})
fi
# Look for sasoperator namespaces
echo 'DEBUG: Looking for SAS Deployment Operator namespaces' >> $logfile
sasoperatorns=($($KUBECTLCMD get deploy -l 'app.kubernetes.io/name=sas-deployment-operator' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [ ${#sasoperatorns[@]} -gt 0 ]; then
    namespaces+=(${sasoperatorns[@]})
    for SASOPERATOR_NS in ${sasoperatorns[@]}; do
        echo -e "SASOPERATOR_NS: $SASOPERATOR_NS" > $TEMPDIR/versions/${SASOPERATOR_NS}_sas-deployment-operator-version.txt
        echo "  - SAS Deployment Operator and sas-orchestration image versions" | tee -a $logfile
        # Check sasoperator mode
        if [[ $($KUBECTLCMD -n $SASOPERATOR_NS get deploy -l 'app.kubernetes.io/name=sas-deployment-operator' -o jsonpath='{.items[0].spec.template.spec.containers[].env[1].valueFrom}' 2>> $logfile) == '' ]]; then 
            echo -e "SASOPERATOR MODE: Cluster-Wide" >> $TEMPDIR/versions/${SASOPERATOR_NS}_sas-deployment-operator-version.txt
        else
            echo -e "SASOPERATOR MODE: Namespace" >> $TEMPDIR/versions/${SASOPERATOR_NS}_sas-deployment-operator-version.txt
        fi
        createTask "$KUBECTLCMD -n $SASOPERATOR_NS get deploy -l 'app.kubernetes.io/name=sas-deployment-operator' -o jsonpath='{.items[0].spec.template.spec.containers[].image}'" "$TEMPDIR/versions/${SASOPERATOR_NS}_sas-deployment-operator-version.txt"
    done
    if type docker > /dev/null 2>> $logfile; then
        docker image ls 2>> $logfile | grep $(docker image ls 2>> $logfile | grep '^sas-orchestration' | awk '{print $3}') > $TEMPDIR/versions/sas-orchestration-docker-image-version.txt 2>> $logfile
    fi
fi

# Look for Logging and Monitoring namespaces
echo 'DEBUG: Looking for Logging namespaces' >> $logfile
loggingns=($($KUBECTLCMD get sts -l 'app.kubernetes.io/component=v4m-search' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [[ ${#loggingns[@]} -gt 0 ]]; then 
    echo -e "LOGGING_NS: ${loggingns[@]}" >> $logfile
    namespaces+=(${loggingns[@]})
fi
echo 'DEBUG: Looking for Monitoring namespaces' >> $logfile
monitoringns=($($KUBECTLCMD get deploy -l 'app.kubernetes.io/name=grafana' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [[ ${#monitoringns[@]} -gt 0 ]]; then 
    echo -e "MONITORING_NS: ${monitoringns[@]}" >> $logfile
    namespaces+=(${monitoringns[@]})
    $KUBECTLCMD -n ${monitoringns[0]} get cm v4m-metrics -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' > $TEMPDIR/versions/${monitoringns[0]}_v4m-version.txt 2>> $logfile
fi

# get iac-dac-files
if [[ ! -z $TFVARSFILE ]]; then
    mkdir -p $TEMPDIR/iac-dac-files
    echo "  - Collecting iac information" | tee -a $logfile
    cp $TFVARSFILE $TEMPDIR/iac-dac-files/terraform.tfvars
    removeSensitiveData $TEMPDIR/iac-dac-files/terraform.tfvars
fi
if [[ ! -z $ANSIBLEVARSFILES ]]; then
    mkdir -p $TEMPDIR/iac-dac-files
    echo "  - Collecting dac information" | tee -a $logfile
    for file in ${ANSIBLEVARSFILES[@]}; do
        cp ${file%%#*} $TEMPDIR/iac-dac-files/${file#*#}-ansible-vars.yaml
        removeSensitiveData $TEMPDIR/iac-dac-files/${file#*#}-ansible-vars.yaml
    done
fi

hasCertManagerCRD='false'
hasCrunchyDataCRD='false'
hasEspCRD='false'
hasMonitoringCRD='false'
hasOrchestrationCRD='false'
hasMetricsServer='false'

mkdir -p $TEMPDIR/kubernetes/clusterwide
mv $k8sApiResources $TEMPDIR/kubernetes/clusterwide/api-resources.txt

if grep cert-manager.io $TEMPDIR/kubernetes/clusterwide/api-resources.txt > /dev/null 2>&1; then hasCertManagerCRD='true'; fi
if grep postgres-operator.crunchydata.com $TEMPDIR/kubernetes/clusterwide/api-resources.txt > /dev/null 2>&1; then hasCrunchyDataCRD='v5'
  elif grep pgclusters.crunchydata.com $TEMPDIR/kubernetes/clusterwide/api-resources.txt > /dev/null 2>&1; then hasCrunchyDataCRD='v4'; fi
if grep iot.sas.com $TEMPDIR/kubernetes/clusterwide/api-resources.txt > /dev/null 2>&1; then hasEspCRD='true'; fi
if grep monitoring.coreos.com $TEMPDIR/kubernetes/clusterwide/api-resources.txt > /dev/null 2>&1; then hasMonitoringCRD='true'; fi
if grep orchestration.sas.com $TEMPDIR/kubernetes/clusterwide/api-resources.txt > /dev/null 2>&1; then hasOrchestrationCRD='true'; fi
if grep metrics.k8s.io $TEMPDIR/kubernetes/clusterwide/api-resources.txt > /dev/null 2>&1; then hasMetricsServer='true'; fi

clusterobjects=(clusterrolebindings clusterroles customresourcedefinitions namespaces nodes persistentvolumes storageclasses)
if [[ $hasCertManagerCRD == 'true' ]]; then clusterobjects+=(clusterissuers); fi
if [[ $hasMetricsServer == 'true' ]]; then clusterobjects+=(nodemetrics); fi
if [[ $isOpenShift == 'true' ]]; then clusterobjects+=(projects); fi

echo "  - Collecting cluster wide information" | tee -a $logfile
mkdir -p $TEMPDIR/kubernetes/clusterwide/get $TEMPDIR/kubernetes/clusterwide/describe $TEMPDIR/kubernetes/clusterwide/json $TEMPDIR/kubernetes/clusterwide/yaml $TEMPDIR/kubernetes/clusterwide/top

# get cluster objects
echo "    - kubectl get" | tee -a $logfile
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    createTask "$KUBECTLCMD get $object -o wide" "$TEMPDIR/kubernetes/clusterwide/get/$object.txt"
done
# describe cluster objects
echo "    - kubectl describe" | tee -a $logfile
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    createTask "$KUBECTLCMD describe $object" "$TEMPDIR/kubernetes/clusterwide/describe/$object.txt"  
done
# get yaml cluster objects
echo "    - kubectl get -o yaml" | tee -a $logfile
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    createTask "$KUBECTLCMD get $object -o yaml" "$TEMPDIR/kubernetes/clusterwide/yaml/$object.yaml"
done
# get json cluster objects
echo "    - kubectl get -o json" | tee -a $logfile
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    createTask "$KUBECTLCMD get $object -o json" "$TEMPDIR/kubernetes/clusterwide/json/$object.json"
done
# kubectl top nodes
echo "    - kubectl top nodes" | tee -a $logfile
if [[ $KUBECTLCMD == 'kubectl' ]]; then
    createTask "$KUBECTLCMD top node" "$TEMPDIR/kubernetes/clusterwide/top/nodes.txt"
else
    createTask "$KUBECTLCMD adm top node" "$TEMPDIR/kubernetes/clusterwide/top/nodes.txt"
fi

if [[ "$PERFORMANCE" = true ]]; then
    # Capturing performance information
    echo "  - Collecting nodes performance information" | tee -a $logfile
    performanceTasks
fi

# Collect information from selected namespaces
getNamespaceData ${namespaces[@]}

echo "  - Kubernetes and Kustomize versions" | tee -a $logfile
$KUBECTLCMD version -o yaml > $TEMPDIR/versions/kubernetes.txt 2>> $logfile
cat $TEMPDIR/versions/kubernetes.txt >> $logfile
if type kustomize > /dev/null 2>> $logfile; then
    kustomize version -o yaml > $TEMPDIR/versions/kustomize.txt 2>> $logfile
    cat $TEMPDIR/versions/kustomize.txt >> $logfile
fi

# Capturing nodes time information
echo "  - Capturing nodes time information" | tee -a $logfile
nodesTimeReport

# Collect deployment assets
if [ $DEPLOYPATH != 'unavailable' ]; then
    echo "  - Collecting deployment assets" | tee -a $logfile
    mkdir $TEMPDIR/assets 2>> $logfile
    cd $DEPLOYPATH 2>> $logfile
    find . -path ./sas-bases -prune -false -o \( -name "*.yaml" -o -path "*sas-risk*" -type f -name "*.env" \) 2>> $logfile | grep -vE '\./.*sas-bases.*/.*' | tar -cf $TEMPDIR/assets/assets.tar -T - 2>> $logfile
    tar xf $TEMPDIR/assets/assets.tar --directory $TEMPDIR/assets 2>> $logfile
    rm -rf $TEMPDIR/assets/assets.tar 2>> $logfile
    removeSensitiveData $(find $TEMPDIR/assets -type f)
    if [[ -d ./sas-bases ]]; then
        cp -R ./sas-bases $TEMPDIR/assets/sas-bases 2>> $logfile
    fi
fi

# Wait for pending tasks
waitForTasks

# Generate kviya reports
for namespace in ${namespaces[@]}; do
    if [[ ! -d $TEMPDIR/kubernetes/$namespace/.kviya ]]; then
        generateKviyaReport $namespace
    fi
done
if [[ -f $TEMPDIR/.get-k8s-info/sendToCase.out ]]; then
    echo -e "\n\nIf you have not already done so, please provide the following information to SAS Technical Support when opening or updating the Case:\n" | tee -a $logfile
    cat $TEMPDIR/.get-k8s-info/sendToCase.out | tee -a $logfile
    echo '' | tee -a $logfile
    rm $TEMPDIR/.get-k8s-info/sendToCase.out
fi
rm -rf $TEMPDIR/.kviya

cp $logfile $TEMPDIR/.get-k8s-info
tar -czf $outputFile --directory=$TEMPDIR .
if [ $? -eq 0 ]; then
    if [ $SASTSDRIVE == 'true' ]; then
        tput cnorm
        echo -e "\nDone! File '$outputFile' was successfully created."
        # use an sftp batch file since the user password is expected from stdin
        cat > $TEMPDIR/SASTSDrive.batch <<< "put $outputFile $CASENUMBER"
        echo -e "\nINFO: Performing SASTSDrive login. Use only an email that was authorized by SAS Tech Support for the case\n"
        read -p " -> SAS Profile Email: " EMAIL
        echo ''
        sftp -oPubkeyAuthentication=no -oPasswordAuthentication=no -oNumberOfPasswordPrompts=2 -oConnectTimeout=1 -oBatchMode=no -b $TEMPDIR/SASTSDrive.batch "${EMAIL}"@sft.sas.com > /dev/null
        if [ $? -ne 0 ]; then 
            echo -e "\nERROR: Failed to send the '$outputFile' file to SASTSDrive through sftp. Will not retry."
            echo -e "\nSend the '$outputFile' file to SAS Tech Support using a browser (https://support.sas.com/kb/65/014.html#upload) or through the case.\n"
            cleanUp 1
        else 
            echo -e "\nFile successfully sent to SASTSDrive.\n"
            cleanUp 0
        fi
    else
        echo -e "\nDone! File '$outputFile' was successfully created. Send it to SAS Tech Support.\n"
        cleanUp 0
    fi
else
    echo "\nERROR: Failed to save output file '$outputFile'."
    cleanUp 1
fi