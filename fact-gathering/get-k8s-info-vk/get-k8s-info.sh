#!/bin/bash
# This script captures information from Kubernetes cluster with a Viya 4 deployment.
# Date: 04MAY2023
#
# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
version='get-k8s-info v1.3.12'

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
    echo "  --disabletags    (Optional) Disable specific debug tags. By default, all tags are enabled."
    echo "                              Available values are: 'backups', 'config', 'postgres' and 'rabbitmq'"
    echo "  -s|--sastsdrive  (Optional) Send the .tgz file to SASTSDrive through sftp."
    echo "                              Only use this option after you were authorized by Tech Support to send files to SASTSDrive for the case."
    echo "  -w|--workers     (Optional) Number of simultaneous "kubectl" commands that the script can execute in parallel."
    echo "                              If not specified, 5 workers are used by default."
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

# Handle ctrl+c
trap cleanUp SIGINT
function cleanUp() {
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

# Check for updates
latestVersion=$(curl -s https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/get-k8s-info-vk/get-k8s-info.sh 2>> $logfile | grep '^version=' | cut -d "'" -f2)
if [[ ! -z $latestVersion ]]; then
    if [[ $(cut -d 'v' -f2 <<< $latestVersion | tr -d '.') -gt $(version | cut -d 'v' -f2 | tr -d '.') ]]; then
        echo "WARNING: A new version is available! ($latestVersion)" | tee -a $logfile
        read -p "WARNING: It is highly recommended to use the latest version. Do you want to update this script ($(version))? (y/n) " k
        echo "DEBUG: Wants to update? $k" >> $logfile
        if [ "$k" == 'y' ] || [ "$k" == 'Y' ] ; then
            updatedScript=$(mktemp)
            curl -s -o $updatedScript https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/get-k8s-info-vk/get-k8s-info.sh >> $logfile 2>&1
            scriptPath=$(dirname $(realpath -s $0))
            if cp $updatedScript $scriptPath/$script > /dev/null 2>> $logfile; then echo -e "INFO: Script updated successfully. Restarting...\n";rm -f $updatedScript;$scriptPath/$script ${@};exit $?;else echo -e "ERROR: Script update failed!\n\nINFO: Update it manually from https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/get-k8s-info-vk" | tee -a $logfile;cleanUp 1;fi
        fi
    fi
fi

# Check kubectl
if type kubectl > /dev/null 2>> $logfile; then
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

# Initialize Variables
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
      shift # past argument
      shift # past value
      ;;
    --debugtag|--debugtags)
      echo -e "WARNING: The '--debugtag' option is deprecated. All debug tags are already enabled by default.\n" | tee -a $logfile
      shift # past argument
      shift # past value
      ;;
    -d)
      usage
      echo -e "\nERROR: The '-d' option is deprecated. All debug tags are already enabled by default. In the future, '-d' will be used to DISABLE specific debug tags." | tee -a $logfile
      cleanUp 1
      ;;
    --disabletag|--disabletags)
      TAGS=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      if [[ $TAGS =~ 'postgres' ]]; then POSTGRES=false;fi
      if [[ $TAGS =~ 'rabbitmq' ]]; then RABBITMQ=false;fi
      if [[ $TAGS =~ 'config' || $TAGS =~ 'consul' ]]; then CONFIG=false;fi
      if [[ $TAGS =~ 'backup' ]]; then BACKUPS=false;fi
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
      timeout 5 bash -c 'cat < /dev/null > /dev/tcp/sft.sas.com/22' > /dev/null 2>> $logfile
      if [ $? -ne 0 ]; then
          echo -e "WARNING: Connection to SASTSDrive not available. The script won't try to send the .tgz file to SASTSDrive.\n" | tee -a $logfile
      else SASTSDRIVE="true"; fi
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
        fi
    else
        TFVARSFILE=''
    fi
fi
echo TFVARSFILE: $TFVARSFILE >> $logfile
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
    touch $OUTPATH/${CASENUMBER}.tgz 2>> $logfile
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to write output file '$OUTPATH/${CASENUMBER}.tgz'." | tee -a $logfile
        cleanUp 1
    fi
fi

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
        if [[ " ${viyans[*]} " =~ " ${ns} " ]]; then hasViya=true; fi
        if [[ ! " ${namespaces[*]} " =~ " ${ns} " ]]; then namespaces+=($ns); fi
    done
    if [ $hasViya == false ]; then
        echo "WARNING: No Viya deployments were found in any of the namespaces provided" | tee -a $logfile
        echo "WARNING: The script will continue capturing information from the namespaces provided and Viya related namespaces" | tee -a $logfile
    fi
fi

# Check if the viya4-deployment project was used
if [ -z $ANSIBLEVARSFILE ]; then
    for ns in $(echo $USER_NS | tr ',' ' '); do
        if $KUBECTLCMD -n $ns get cm sas-deployment-buildinfo > /dev/null 2>&1; then 
            read -p " -> The viya4-deployment project was used to deploy the environment in the $ns namespace. Specify the path of the "ansible-vars.yaml" file that was used (leave blank if not known): " ANSIBLEVARSFILE
            ANSIBLEVARSFILE="${ANSIBLEVARSFILE/#\~/$HOME}"
        fi
        if [ ! -z $ANSIBLEVARSFILE ]; then 
            ANSIBLEVARSFILE=$(realpath $ANSIBLEVARSFILE 2> /dev/null)
            if [ -d $ANSIBLEVARSFILE ]; then ANSIBLEVARSFILE="$ANSIBLEVARSFILE/ansible-vars.yaml";fi
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
    if [ -d $ANSIBLEVARSFILE ]; then ANSIBLEVARSFILE="$ANSIBLEVARSFILE/ansible-vars.yaml";fi
    if [ ! -f $ANSIBLEVARSFILE ]; then 
        echo "ERROR: --ansiblevars file '$ANSIBLEVARSFILE' doesn't exist" | tee -a $logfile
        cleanUp 1
    else
        # include dac namespace
        dacns=$(grep 'NAMESPACE: ' $ANSIBLEVARSFILE 2>> $logfile | cut -d ' ' -f2)
        if [[ ! -z $dacns && " ${viyans[*]} " =~ " $dacns " ]]; then
            viyans+=($dacns)
        elif [[ -z $dacns ]]; then
            dacns='none'
        fi
        ANSIBLEVARSFILES+=("$ANSIBLEVARSFILE#$dacns")
    fi
fi
echo ANSIBLEVARSFILES: ${ANSIBLEVARSFILES[*]} >> $logfile

function removeSensitiveData {
    for file in $@; do
        echo "        - Removing sensitive data from ${file#*/*/*/}" | tee -a $logfile
        isSensitive='false'
        userContent='false'
        # If file contains Secrets
        if [ $(grep -c '^kind: Secret$' $file) -gt 0 ]; then
            secretStartLines=($(grep -n '^---$\|^kind: Secret$' $file | grep 'kind: Secret' -B1 | grep -v Secret | cut -d ':' -f1))
            secretEndLines=($(grep -n '^---$\|^kind: Secret$' $file | grep 'kind: Secret' -A1 | grep -v Secret | cut -d ':' -f1))
            sed -n 1,$[ ${secretStartLines[0]} -1 ]p $file > $file.parsed 2>> $logfile
            printf '%s\n' "---" >> $file.parsed 2>> $logfile
            i=0
            while [ $i -lt ${#secretStartLines[@]} ]
            do
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
                done < <(sed -n ${secretStartLines[i]},${secretEndLines[i]}p $file 2>> $logfile)
                i=$[ $i + 1 ]
                if [ $i -lt ${#secretStartLines[@]} ]; then printf '%s\n' "---" >> $file.parsed 2>> $logfile; fi
            done
            sed -n ${secretEndLines[-1]},\$p $file >> $file.parsed 2>> $logfile
        else
            while IFS="" read -r p || [ -n "$p" ]
            do
                if [ ${file##*/} == 'sas-consul-server_sas-bootstrap-config_kv_read.txt' ]; then
                    # New key
                    if [[ "${p}" =~ 'config/' || "${p}" =~ 'configurationservice/' ]]; then
                        isSensitive='false'
                        if [[ "${p}" =~ '-----BEGIN' || "${p}" =~ 'password=' || "${p}" =~ '"password":"' ]]; then
                            isSensitive='true'
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
                #elif [ ${file##*.} == 'yaml' ]; then
                else
                    if [[ ( $userContent == 'false' ) && ( "${p}" =~ ':' || "${p}" == '---' ) ]]; then
                        isSensitive='false'
                        # Check for Certificates or HardCoded Passwords
                        if [[ "${p}" =~ '-----BEGIN ' || $p =~ 'ssword: ' ]]; then
                            isSensitive='true'
                            printf '%s: %s\n' "${p%%:*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                        else
                            printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                        fi
                        if [[ "${p}" == '  User Content:' || "${p}" == '  userContent:' ]]; then
                            userContent='true'
                            printf '%s\n' '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                        fi
                    # Print only if not sensitive and not sasdeployment "User content"
                    elif [ $isSensitive == 'false' ]; then
                        if [ $userContent == 'true' ]; then 
                            if [[ "${p}" == 'Status:' || "${p}" == 'status:' ]]; then
                                userContent='false'
                                printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                            fi
                        else
                            printf '%s\n' "${p}" >> $file.parsed 2>> $logfile
                        fi
                    fi
                fi
            done < $file
        fi
        rm -f $file 2>> $logfile
        mv $file.parsed $file 2>> $logfile
    done
}
# begin kviya functions
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
    cat $TEMPDIR/.kviya/work/nodeMon.out $TEMPDIR/.kviya/work/podMon.out > $TEMPDIR/reports/kviya-report_$namespace.txt
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
            if $KUBECTLCMD -n ${pod%%/*} exec ${pod#*/} -- date -u > /dev/null 2>&1; then
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
        nodeDate=$(cat $TEMPDIR/.get-k8s-info/nodesTimeReport/node$nodeIndex.out)
        echo -e "    - ${nodes[$nodeIndex]}\t$nodeDate" | tee -a $logfile
        echo -e "${nodes[$nodeIndex]}\t$nodeDate" >> $TEMPDIR/reports/nodes-time-report.txt
    done

    if [[ -s $TEMPDIR/.get-k8s-info/nodesTimeReport/jump.out ]]; then
        jumpDate=$(cat $TEMPDIR/.get-k8s-info/nodesTimeReport/jump.out)
    fi
    echo -e "\nJumpbox time: $jumpDate" >> $TEMPDIR/reports/nodes-time-report.txt
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
    echo $1\$$2 >> $TEMPDIR/.get-k8s-info/taskmanager/tasks
}
function runTask() {
    task=$1
    taskCommand=$(sed "$task!d" $TEMPDIR/.get-k8s-info/taskmanager/tasks | cut -d '$' -f1)
    taskOutput=$(sed "$task!d" $TEMPDIR/.get-k8s-info/taskmanager/tasks | cut -d '$' -f2)
    echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] [Task #$task] - Executing" >> $TEMPDIR/.get-k8s-info/workers/workers.log
    eval ${taskCommand} > ${taskOutput} 2> $TEMPDIR/.get-k8s-info/workers/worker${worker}/syserr.log
    if [[ $? -ne 0 ]]; then
        echo -e "\nTask #$task: $taskCommand > ${taskOutput}" | cat - $TEMPDIR/.get-k8s-info/workers/worker${worker}/syserr.log >> $TEMPDIR/.get-k8s-info/kubectl_errors.log
    fi
    echo $task >> $TEMPDIR/.get-k8s-info/workers/worker${worker}/completedTasks
    echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] [Task #$task] - Finished" >> $TEMPDIR/.get-k8s-info/workers/workers.log
}
function taskWorker() {
    worker=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S:%N") [Worker #$worker] - Started" >> $TEMPDIR/.get-k8s-info/workers/workers.log
    currentTask=0
    lastTask=0

    mkdir $TEMPDIR/.get-k8s-info/workers/worker$worker
    touch $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks
    touch $TEMPDIR/.get-k8s-info/workers/worker${worker}/completedTasks
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
        monitoringobjects=(alertmanagerconfigs alertmanagers podmonitors probes prometheusagents prometheuses prometheusrules scrapeconfigs servicemonitors thanosrulers)
        nginxobjects=(ingresses)
        openshiftobjects=(routes securitycontextconstraints)
        orchestrationobjects=(sasdeployments)
        viyaobjects=(casdeployments dataservers distributedredisclusters opendistroclusters)

        getobjects=(configmaps cronjobs daemonsets deployments endpoints events horizontalpodautoscalers jobs persistentvolumeclaims poddisruptionbudgets pods podtemplates replicasets rolebindings roles secrets serviceaccounts services statefulsets)
        describeobjects=(configmaps cronjobs daemonsets deployments endpoints horizontalpodautoscalers jobs persistentvolumeclaims poddisruptionbudgets pods podtemplates replicasets rolebindings roles secrets serviceaccounts services statefulsets)
        yamlobjects=(configmaps cronjobs daemonsets deployments endpoints horizontalpodautoscalers jobs persistentvolumeclaims poddisruptionbudgets pods podtemplates replicasets rolebindings roles serviceaccounts services statefulsets)

        if [[ $hasMonitoringCRD == 'true' ]]; then
            getobjects+=(${monitoringobjects[@]})
            describeobjects+=(${monitoringobjects[@]})
            yamlobjects+=(${monitoringobjects[@]})
        fi
        if [[ $isOpenShift == 'true' ]]; then
            getobjects+=(${openshiftobjects[@]})
            describeobjects+=(${openshiftobjects[@]})
            yamlobjects+=(${openshiftobjects[@]})
        else
            getobjects+=(${nginxobjects[@]})
            describeobjects+=(${nginxobjects[@]})
            yamlobjects+=(${nginxobjects[@]})
        fi
        if [[ $hasOrchestrationCRD == 'true' ]]; then
            getobjects+=(${orchestrationobjects[@]})
            describeobjects+=(${orchestrationobjects[@]})
            yamlobjects+=(${orchestrationobjects[@]})
        fi
        
        if [ ! -d $TEMPDIR/kubernetes/$namespace ]; then
            echo "  - Collecting information from the '$namespace' namespace" | tee -a $logfile
            mkdir -p $TEMPDIR/kubernetes/$namespace/describe $TEMPDIR/kubernetes/$namespace/get $TEMPDIR/kubernetes/$namespace/yaml

            # If this namespace contains a Viya deployment
            if [[ " ${viyans[*]} " =~ " ${namespace} " ]]; then
                isViyaNs='true'

                getobjects+=(${viyaobjects[@]})
                describeobjects+=(${viyaobjects[@]})
                yamlobjects+=(${viyaobjects[@]})

                if [[ $hasCertManagerCRD == 'true' ]]; then
                    getobjects+=(${certmanagerobjects[@]})
                    describeobjects+=(${certmanagerobjects[@]})
                    yamlobjects+=(${certmanagerobjects[@]})
                fi
                if [[ $hasCrunchyDataCRD != 'false' ]]; then
                    if [[ $hasCrunchyDataCRD == 'v5' ]]; then
                        getobjects+=(${crunchydata5objects[@]})
                        describeobjects+=(${crunchydata5objects[@]})
                        yamlobjects+=(${crunchydata5objects[@]})
                    else
                        getobjects+=(${crunchydata4objects[@]})
                        describeobjects+=(${crunchydata4objects[@]})
                        yamlobjects+=(${crunchydata4objects[@]})
                    fi
                fi
                if [[ $hasEspCRD == 'true' ]]; then
                    getobjects+=(${espobjects[@]})
                    describeobjects+=(${espobjects[@]})
                    yamlobjects+=(${espobjects[@]})
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
                        $KUBECTLCMD -n $namespace exec $consulPod -c sas-consul-server -- bash -c "export CONSUL_HTTP_ADDR=https://localhost:8500;/opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse" > $TEMPDIR/kubernetes/$namespace/exec/$consulPod/sas-consul-server_sas-bootstrap-config_kv_read.txt 2>> $logfile
                        if [ $? -eq 0 ]; then 
                            removeSensitiveData $TEMPDIR/kubernetes/$namespace/exec/$consulPod/sas-consul-server_sas-bootstrap-config_kv_read.txt
                            break
                        fi
                    done
                fi
                # postgres debugtag
                if [[ "$POSTGRES" = true ]]; then
                    echo "    - Getting postgres information" | tee -a $logfile
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
                                for crunchyPod in $($KUBECTLCMD -n $namespace get pod -l "postgres-operator.crunchydata.com/data=postgres,postgres-operator.crunchydata.com/cluster=$pgcluster" --no-headers 2>> $logfile | awk '{print $1}'); do
                                    mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$crunchyPod
                                    createTask "$KUBECTLCMD -n $namespace exec $crunchyPod -c database -- patronictl list" "$TEMPDIR/kubernetes/$namespace/exec/$crunchyPod/database_patronictl_list.txt"
                                done
                            fi
                        done
                    fi
                fi
                # rabbitmq debugtag
                if [[ "$RABBITMQ" = true ]]; then
                    echo "    - Getting rabbitmq information" | tee -a $logfile
                    for rabbitmqPod in $($KUBECTLCMD -n $namespace get pod -l 'app=sas-rabbitmq-server' --no-headers 2>> $logfile | awk '{print $1}'); do
                        mkdir -p $TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod
                        createTask "$KUBECTLCMD -n $namespace exec $rabbitmqPod -c sas-rabbitmq-server -- bash -c 'source /rabbitmq/data/.bashrc;/opt/sas/viya/home/lib/rabbitmq-server/sbin/rabbitmqctl report'" "$TEMPDIR/kubernetes/$namespace/exec/$rabbitmqPod/sas-rabbitmq-server_rabbitmqctl_report.txt"
                    done
                fi
                # Check if we should wait for cas logs
                casDefaultControllerPod=$($KUBECTLCMD -n $namespace get pod -l casoperator.sas.com/node-type=controller,casoperator.sas.com/server=default --no-headers 2>> $logfile | awk '{print $1}')
                if [[ (-z $casDefaultControllerPod || $($KUBECTLCMD -n $namespace get pod $casDefaultControllerPod --no-headers 2>> $logfile | awk '{print $5}' | grep -cE '^[0-9]+s$') -gt 0) ]]; then
                    waitForCasTimeout=$[ $(date +%s) + 120 ]
                    waitForCas $namespace $casDefaultControllerPod &
                    waitForCasPid=$!
                    echo $waitForCasPid:$waitForCasTimeout:$namespace >> $TEMPDIR/.get-k8s-info/waitForCas
                fi
                # backups debugtag
                if [[ "$BACKUPS" = true ]]; then
                    echo "    - Getting backups information" | tee -a $logfile
                    # Information from backup PVCs
                    for backupPod in $($KUBECTLCMD -n $namespace get pod -l 'sas.com/backup-job-type in (scheduled-backup,scheduled-backup-incremental,restore,purge-backup)' --no-headers 2>> $logfile | grep ' NotReady \| Running ' | awk '{print $1}'); do
                        # sas-common-backup-data PVC
                        podContainer=$($KUBECTLCMD -n $namespace get pod $backupPod -o jsonpath={.spec.containers[0].name} 2>> $logfile)
                        if $KUBECTLCMD -n $namespace exec $backupPod -c $podContainer -- df -h /sasviyabackup 2>> $logfile > /dev/null; then
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
                        mkdir -p $TEMPDIR/kubernetes/$namespace/exec/sas-cas-server-default-controller
                        $KUBECTLCMD -n $namespace exec sas-cas-server-default-controller -c sas-backup-agent 2>> $logfile -- bash -c 'ls -lRa /sasviyabackup' > $TEMPDIR/kubernetes/$namespace/exec/sas-cas-server-default-controller/sas-backup-agent_ls_sasviyabackups.txt 2>> $logfile
                        $KUBECTLCMD -n $namespace exec sas-cas-server-default-controller -c sas-backup-agent -- find /sasviyabackup -name status.json -exec echo "{}:" \; -exec cat {} \; -exec echo -e '\n' \; > $TEMPDIR/kubernetes/$namespace/exec/sas-cas-server-default-controller/sas-backup-agent_find_status.json.txt 2>> $logfile
                    fi
                    # Past backup and restore status
                    $KUBECTLCMD -n $namespace get jobs -l "sas.com/backup-job-type in (scheduled-backup, scheduled-backup-incremental)" -L "sas.com/sas-backup-id,sas.com/backup-job-type,sas.com/sas-backup-job-status,sas.com/sas-backup-persistence-status,sas.com/sas-backup-datasource-types,sas.com/sas-backup-include-postgres" --sort-by=.status.startTime > $TEMPDIR/reports/backup-status_$namespace.txt 2>> $logfile
                    $KUBECTLCMD -n $namespace get jobs -l "sas.com/backup-job-type=restore" -L "sas.com/sas-backup-id,sas.com/backup-job-type,sas.com/sas-restore-id,sas.com/sas-restore-status,sas.com/sas-restore-tenant-status-provider" > $TEMPDIR/reports/restore-status_$namespace.txt 2>> $logfile
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
                if [ $object == 'replicasets' ]; then 
                    # describe only active replicasets
                    createTask "$KUBECTLCMD -n $namespace describe $object $($KUBECTLCMD -n $namespace get $object --no-headers 2>> $logfile | awk '{if ($2 > 0)print $1}' | tr '\n' ' ')" "$TEMPDIR/kubernetes/$namespace/describe/$object.txt"
                elif [[ $object == 'sasdeployments' && $isViyaNs == 'true' ]]; then 
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
                if [ $object == 'replicasets' ]; then
                    createTask "$KUBECTLCMD -n $namespace get $object $($KUBECTLCMD -n $namespace get $object --no-headers 2>> $logfile | awk '{if ($2 > 0)print $1}' | tr '\n' ' ') -o yaml" "$TEMPDIR/kubernetes/$namespace/yaml/$object.yaml"
                elif [[ $object == 'sasdeployments' && $isViyaNs == 'true' ]]; then
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
            # kubectl top pods
            echo "    - kubectl top pod" | tee -a $logfile
            if [[ $isOpenShift == 'false' ]]; then
                mkdir -p $TEMPDIR/kubernetes/$namespace/top
                createTask "$KUBECTLCMD -n $namespace top pod" "$TEMPDIR/kubernetes/$namespace/top/pods.txt"
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
    if [[ $isOpenShift == 'false' ]]; then
        cp $TEMPDIR/kubernetes/clusterwide/top/nodes.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/nodesTop.out 2>> $logfile
        cp $TEMPDIR/kubernetes/$namespace/top/pods.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/podsTop.out 2>> $logfile
    else
        touch $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/nodesTop.out $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/podsTop.out
    fi
    if [[ " ${viyans[@]} " =~ " $namespace " ]]; then
        # Generate kviya report
        echo "DEBUG: Generating kviya report for namespace $namespace" >> $logfile
        kviyaReport $namespace
    fi
    tar -czf $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime.tgz --directory=$TEMPDIR/kubernetes/$namespace/.kviya $saveTime 2>> $logfile
    rm -rf $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime 2>> $logfile
}
function captureDiagramToolFiles {
    echo 'DEBUG: Capturing JSON files used by the K8S Diagram Tool' >> $logfile
    mkdir -p $TEMPDIR/.diagram-tool
    date -u +"%Y-%m-%dT%H:%M:%SZ" > $TEMPDIR/.diagram-tool/date.txt 2>> $logfile
    createTask "$KUBECTLCMD get configmaps --all-namespaces -o json" "$TEMPDIR/.diagram-tool/configmaps.txt"
    createTask "$KUBECTLCMD get customresourcedefinitions -o json" "$TEMPDIR/.diagram-tool/crd.txt"
    createTask "$KUBECTLCMD get daemonsets --all-namespaces -o json" "$TEMPDIR/.diagram-tool/daemonsets.txt"
    createTask "$KUBECTLCMD get deployments --all-namespaces -o json" "$TEMPDIR/.diagram-tool/deployments.txt"
    createTask "$KUBECTLCMD get endpoints --all-namespaces -o json" "$TEMPDIR/.diagram-tool/endpoints.txt"
    createTask "$KUBECTLCMD get events --all-namespaces -o json" "$TEMPDIR/.diagram-tool/events.txt"
    createTask "$KUBECTLCMD get ingresses --all-namespaces -o json" "$TEMPDIR/.diagram-tool/ingress.txt"
    createTask "$KUBECTLCMD get jobs --all-namespaces -o json" "$TEMPDIR/.diagram-tool/jobs.txt"
    if [[ $isOpenShift == 'false' ]]; then
        createTask "$KUBECTLCMD get namespaces -o json" "$TEMPDIR/.diagram-tool/namespaces.txt"
    else
        createTask "$KUBECTLCMD get projects -o json" "$TEMPDIR/.diagram-tool/namespaces.txt"
    fi
    createTask "$KUBECTLCMD get nodes -o json" "$TEMPDIR/.diagram-tool/nodes.txt"
    createTask "$KUBECTLCMD get persistentvolumeclaims --all-namespaces -o json" "$TEMPDIR/.diagram-tool/pvcs.txt"
    createTask "$KUBECTLCMD get persistentvolumes -o json" "$TEMPDIR/.diagram-tool/pvs.txt"
    createTask "$KUBECTLCMD get pods --all-namespaces -o json" "$TEMPDIR/.diagram-tool/pods.txt"
    createTask "$KUBECTLCMD get replicasets --all-namespaces -o json" "$TEMPDIR/.diagram-tool/replicasets.txt"
    createTask "$KUBECTLCMD get services --all-namespaces -o json" "$TEMPDIR/.diagram-tool/services.txt"
    createTask "$KUBECTLCMD get statefulsets --all-namespaces -o json" "$TEMPDIR/.diagram-tool/statefulsets.txt"
    createTask "$KUBECTLCMD get storageclasses -o json" "$TEMPDIR/.diagram-tool/sc.txt"
}
function waitForTasks {
    touch $TEMPDIR/.get-k8s-info/taskmanager/endsignal

    loading='/'
    assignedTasks=0
    completedTasks=0
    totalTasks=0

    echo -e '\nWaiting for tasks to finish:\n'
    while [[ $completedTasks -lt $totalTasks || $totalTasks -eq 0 ]]; do
        newCompletedTasks=$(cat $TEMPDIR/.get-k8s-info/taskmanager/completed)
        newAssignedTasks=$(cat $TEMPDIR/.get-k8s-info/taskmanager/assigned)
        if [[ ! -z $newCompletedTasks && ! -z $newAssignedTasks ]]; then
            newTotalTasks=$(cat $TEMPDIR/.get-k8s-info/taskmanager/total)
            if [[ ! -z $newTotalTasks ]]; then 
                completedTasks=$newCompletedTasks
                assignedTasks=$newAssignedTasks
                totalTasks=$newTotalTasks
            fi
        fi

        if [ $loading == '/' ]; then loading='-'
        elif [ $loading == '-' ]; then loading='\'
        elif [ $loading == '\' ]; then loading='|'
        elif [ $loading == '|' ]; then loading='/'
        fi

        if [[ -f $TEMPDIR/.get-k8s-info/taskmanager/pid ]]; then
            echo -e "$loading Completed: $completedTasks Pending: $[ $totalTasks - $completedTasks ] Unassigned: $[ $totalTasks - $assignedTasks ] Running: $[ $assignedTasks - $completedTasks ]\n"

            for worker in $(seq 1 $WORKERS); do
                taskCommand=''
                task=$(tail -1 $TEMPDIR/.get-k8s-info/workers/worker${worker}/assignedTasks)
                taskCommand=$(sed "$task!d" $TEMPDIR/.get-k8s-info/taskmanager/tasks | cut -d '$' -f1)
                if [[ ${#taskCommand} -gt 100 ]]; then
                    echo "Worker $worker: ${taskCommand::100} ..."
                else
                    echo "Worker $worker: $taskCommand"
                fi
            done
        else
            echo -e "$loading Completed: $totalTasks Pending: 0 Unassigned: 0 Running: 0"
            break
        fi
        sleep 0.5s
        tput cuu $[ $WORKERS + 2 ]
        tput ed
    done
    echo;

    if [[ -f $TEMPDIR/.get-k8s-info/waitForCas ]]; then
        for line in $(cat $TEMPDIR/.get-k8s-info/waitForCas); do
            waitForCasPid=$(cut -d ':' -f1 <<< $line)
            waitForCasTimeout=$(cut -d ':' -f2 <<< $line)
            waitForCasNamespace=$(cut -d ':' -f3 <<< $line)
            currentTime=$[ $(date +%s) - 30 ]
            if [[ $currentTime -lt $waitForCasTimeout ]]; then
                echo -e "INFO: Waiting $[ $waitForCasTimeout - $currentTime ] seconds for background processes from namespace $waitForCasNamespace to finish"
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
    docker image ls 2>> $logfile | grep $(docker image ls 2>> $logfile | grep '^sas-orchestration' | awk '{print $3}') > $TEMPDIR/versions/sas-orchestration-docker-image-version.txt 2>> $logfile
fi

# Look for Logging and Monitoring namespaces
echo 'DEBUG: Looking for Logging namespaces' >> $logfile
loggingns=($($KUBECTLCMD get deploy -l 'app=eventrouter' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [[ ${#loggingns[@]} -gt 0 ]]; then 
    echo -e "LOGGING_NS: ${loggingns[@]}" >> $logfile
    namespaces+=(${loggingns[@]})
fi
echo 'DEBUG: Looking for Monitoring namespaces' >> $logfile
monitoringns=($($KUBECTLCMD get deploy -l 'app.kubernetes.io/name=grafana' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [[ ${#monitoringns[@]} -gt 0 ]]; then 
    echo -e "MONITORING_NS: ${monitoringns[@]}" >> $logfile
    namespaces+=(${monitoringns[@]})
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

echo "  - Collecting cluster wide information" | tee -a $logfile
clusterobjects=(clusterrolebindings clusterroles customresourcedefinitions namespaces nodes persistentvolumes storageclasses)
if $KUBECTLCMD get crd | grep clusterissuers.cert-manager.io > /dev/null 2>&1; then clusterobjects+=(clusterissuers); fi
if [[ $isOpenShift == 'true' ]]; then clusterobjects+=(projects); fi

# get cluster objects
echo "    - kubectl get" | tee -a $logfile
mkdir -p $TEMPDIR/kubernetes/clusterwide/get
mv $k8sApiResources $TEMPDIR/kubernetes/clusterwide/api-resources.txt
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    if [[ $object == 'customresourcedefinitions' ]]; then
        $KUBECTLCMD get $object -o wide > $TEMPDIR/kubernetes/clusterwide/get/$object.txt 2>> $logfile
    else
        createTask "$KUBECTLCMD get $object -o wide" "$TEMPDIR/kubernetes/clusterwide/get/$object.txt"
    fi
done
# describe cluster objects
echo "    - kubectl describe" | tee -a $logfile
mkdir -p $TEMPDIR/kubernetes/clusterwide/describe
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    createTask "$KUBECTLCMD describe $object" "$TEMPDIR/kubernetes/clusterwide/describe/$object.txt"  
done
# get yaml cluster objects
echo "    - kubectl get -o yaml" | tee -a $logfile
mkdir -p $TEMPDIR/kubernetes/clusterwide/yaml
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    createTask "$KUBECTLCMD get $object -o yaml" "$TEMPDIR/kubernetes/clusterwide/yaml/$object.yaml"
done
# kubectl top nodes
echo "    - kubectl top nodes" | tee -a $logfile
if [[ $isOpenShift == 'false' ]]; then
    mkdir -p $TEMPDIR/kubernetes/clusterwide/top
    createTask "$KUBECTLCMD top node" "$TEMPDIR/kubernetes/clusterwide/top/nodes.txt"
fi

hasCertManagerCRD='false'
hasCrunchyDataCRD='false'
hasEspCRD='false'
hasMonitoringCRD='false'
hasOrchestrationCRD='false'

if grep certificates.cert-manager.io $TEMPDIR/kubernetes/clusterwide/get/customresourcedefinitions.txt > /dev/null 2>&1; then hasCertManagerCRD='true'; fi
if grep postgresclusters.postgres-operator.crunchydata.com $TEMPDIR/kubernetes/clusterwide/get/customresourcedefinitions.txt > /dev/null 2>&1; then hasCrunchyDataCRD='v5'
  elif grep pgclusters $TEMPDIR/kubernetes/clusterwide/get/customresourcedefinitions.txt > /dev/null 2>&1; then hasCrunchyDataCRD='v4'; fi
if grep iot.sas.com $TEMPDIR/kubernetes/clusterwide/get/customresourcedefinitions.txt > /dev/null 2>&1; then hasEspCRD='true'; fi
if grep monitoring.coreos.com $TEMPDIR/kubernetes/clusterwide/get/customresourcedefinitions.txt > /dev/null 2>&1; then hasMonitoringCRD='true'; fi
if grep orchestration.sas.com $TEMPDIR/kubernetes/clusterwide/get/customresourcedefinitions.txt > /dev/null 2>&1; then hasOrchestrationCRD='true'; fi

# Collect files used by the K8S Diagram Tools
captureDiagramToolFiles

# Collect information from selected namespaces
getNamespaceData ${namespaces[@]}

echo "  - Kubernetes and Kustomize versions" | tee -a $logfile
$KUBECTLCMD version --short > $TEMPDIR/versions/kubernetes.txt 2>> $logfile
cat $TEMPDIR/versions/kubernetes.txt >> $logfile
kustomize version --short > $TEMPDIR/versions/kustomize.txt 2>> $logfile
cat $TEMPDIR/versions/kustomize.txt >> $logfile

# Capturing nodes time information
echo "  - Capturing nodes time information" | tee -a $logfile
nodesTimeReport

# Collect deployment assets
if [ $DEPLOYPATH != 'unavailable' ]; then
    echo "  - Collecting deployment assets" | tee -a $logfile
    mkdir $TEMPDIR/assets 2>> $logfile
    cd $DEPLOYPATH 2>> $logfile
    find . -path ./sas-bases -prune -false -o -name "*.yaml" 2>> $logfile | grep -vE '\./.*sas-bases.*/.*' | tar -cf $TEMPDIR/assets/assets.tar -T - 2>> $logfile
    tar xf $TEMPDIR/assets/assets.tar --directory $TEMPDIR/assets 2>> $logfile
    rm -rf $TEMPDIR/assets/assets.tar 2>> $logfile
    removeSensitiveData $(find $TEMPDIR/assets -type f)
fi

# Wait for pending tasks
waitForTasks

# Generate kviya reports
for namespace in ${namespaces[@]}; do
    if [[ ! -d $TEMPDIR/kubernetes/$namespace/.kviya ]]; then
        generateKviyaReport $namespace
    fi
done
rm -rf $TEMPDIR/.kviya

cp $logfile $TEMPDIR/.get-k8s-info
tar -czf $OUTPATH/${CASENUMBER}.tgz --directory=$TEMPDIR .
if [ $? -eq 0 ]; then
    if [ $SASTSDRIVE == 'true' ]; then
        echo -e "\nDone! File '$OUTPATH/${CASENUMBER}.tgz' was successfully created."
        # use an sftp batch file since the user password is expected from stdin
        cat > $TEMPDIR/SASTSDrive.batch <<< "put $OUTPATH/${CASENUMBER}.tgz $CASENUMBER"
        echo -e "\nINFO: Performing SASTSDrive login. Use only an email that was authorized by SAS Tech Support for the case\n"
        read -p " -> SAS Profile Email: " EMAIL
        echo ''
        sftp -oPubkeyAuthentication=no -oPasswordAuthentication=no -oNumberOfPasswordPrompts=2 -oConnectTimeout=1 -oBatchMode=no -b $TEMPDIR/SASTSDrive.batch "${EMAIL}"@sft.sas.com > /dev/null
        if [ $? -ne 0 ]; then 
            echo -e "\nERROR: Failed to send the '$OUTPATH/${CASENUMBER}.tgz' file to SASTSDrive through sftp. Will not retry."
            echo -e "\nSend the '$OUTPATH/${CASENUMBER}.tgz' file to SAS Tech Support using a browser (https://support.sas.com/kb/65/014.html#upload) or through the case.\n"
            cleanUp 1
        else 
            echo -e "\nFile successfully sent to SASTSDrive.\n"
            cleanUp 0
        fi
    else
        echo -e "\nDone! File '$OUTPATH/${CASENUMBER}.tgz' was successfully created. Send it to SAS Tech Support.\n"
        cleanUp 0
    fi
else
    echo "\nERROR: Failed to save output file '$OUTPATH/${CASENUMBER}.tgz'."
    cleanUp 1
fi