#!/bin/bash
# This script captures information from Kubernetes cluster with a Viya 4 deployment.
# Date: 04MAY2023
#
# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

version='get-k8s-info v1.1.10'

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
touch /tmp/get-k8s-info.log
if [[ $? -ne 0 ]]; then 
    echo "ERROR: Unable to write log file '/tmp/get-k8s-info.log'"
    cleanUp 0
else
    logfile='/tmp/get-k8s-info.log'
    echo -e "$version\n$(date -u)\n$(bash --version | head -1)\n$(uname -a)\nCommand: ${0} ${@}\n" > $logfile
fi

function usage {
    echo Version: "$version"
    script=$(echo $0 | rev | cut -d '/' -f1 | rev)
    echo; echo "Usage: $script [OPTIONS]..."
    echo;
    echo "Capture information from a Viya 4 deployment."
    echo;
    echo "  -t|--track       (Optional) SAS Tech Support track number"
    echo "  -n|--namespaces  (Optional) Comma separated list of namespaces"
    echo "  -p|--deploypath  (Optional) Path of the viya \$deploy directory"
    echo "  -o|--out         (Optional) Path where the .tgz file will be created"
    echo "  -l|--logs        (Optional) Capture logs from pods using a comma separated list of label selectors"
    echo "  -d|--debugtags   (Optional) Enable specific debug tags. Available values are: 'cas', 'config' and 'postgres'"
    echo "  -i|--tfvars      (Optional) Path of the terraform.tfvars file"
    echo "  -a|--ansiblevars (Optional) Path of the ansible-vars.yaml file"
    echo "  -s|--sastsdrive  (Optional) Send the .tgz file to SASTSDrive through sftp."
    echo "                             Only use this option after you were authorized by Tech Support to send files to SASTSDrive for the track."
    echo;
    echo "Examples:"
    echo;
    echo "Run the script with no arguments for options to be prompted interactively"
    echo "  $ $script"
    echo;
    echo "You can also specify all options in the command line"
    echo "  $ $script --track 7613123123 --namespace viya-prod --deploypath /home/user/viyadeployment --out /tmp"
    echo;
    echo "Use the '--logs' and '--debugtags' options to collect logs and information from specific components"
    echo "  $ $script --logs 'sas-microanalytic-score,type=esp,workload.sas.com/class=stateful,job-name=' --debugtags 'postgres,cas'"
    echo;
    echo "                                 By: Alexandre Gomes - February 28th 2023"
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
            echo -e "\nScript log saved at: /tmp/get-k8s-info.log"
        else rm -f $logfile; fi
    fi
    if [ -d $TEMPDIR ]; then rm -rf $TEMPDIR; fi
    exit $1
}

# Check kubectl
if type kubectl > /dev/null 2>> $logfile; then
    KUBECTLCMD='kubectl'
elif type oc > /dev/null 2>> $logfile; then
    KUBECTLCMD='oc'
else
    echo;echo "ERROR: Neither 'kubectl' or 'oc' are installed in PATH." | tee -a $logfile
    cleanUp 1
fi

# Check if k8s is OpenShift
if $KUBECTLCMD api-resources 2>> $logfile | grep project.openshift.io > /dev/null; then isOpenShift='true'
else isOpenShift='false';fi

# Initialize Variables
POSTGRES=false
CAS=false
CONFIG=false
SASTSDRIVE=false

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
    -t|--track)
      TRACKNUMBER="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--namespace|--namespaces)
      USER_NS="$2"
      shift # past argument
      shift # past value
      ;;
    -d|--debugtag|--debugtags)
      TAGS=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      if [[ $TAGS =~ 'postgres' ]]; then POSTGRES=true;fi
      if [[ $TAGS =~ 'cas' ]]; then CAS=true;fi
      if [[ $TAGS =~ 'config' ]]; then CONFIG=true;fi
      shift # past argument
      shift # past value
      ;;
    -l|--log|--logs)
      PODLOGS="$2"
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
      echo -e "ERROR: Unknown option $1" | tee -a $logfile
      cleanUp 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

# Check TRACKNUMBER
if [ -z $TRACKNUMBER ]; then 
    if [ $SASTSDRIVE == 'true' ]; then
        read -p " -> SAS Tech Support track number (required): " TRACKNUMBER
    else
        read -p " -> SAS Tech Support track number (leave blank if not known): " TRACKNUMBER
        if [ -z $TRACKNUMBER ]; then TRACKNUMBER=7600000000; fi
    fi
fi
echo TRACKNUMBER: $TRACKNUMBER >> $logfile
if [ $(echo $TRACKNUMBER | egrep -c '^[0-9]{10}$') -ne 1 ]; then
    echo "ERROR: Invalid 10-digit track number" | tee -a $logfile
    cleanUp 1
fi
# Check if an IaC Github Project was used
if [ -z $TFVARSFILE ]; then 
    if $KUBECTLCMD get cm -n kube-system sas-iac-buildinfo > /dev/null 2>&1; then 
        read -p " -> A viya4-iac project was used to create the infrastructure of this environment. Specify the path of the "terraform.tfvars" file that was used (leave blank if not known): " TFVARSFILE
        TFVARSFILE="${TFVARSFILE/#\~/$HOME}"
    fi
fi
if [ ! -z $TFVARSFILE ]; then 
    TFVARSFILE=$(realpath $TFVARSFILE 2> /dev/null)
    if [ -d $TFVARSFILE ]; then TFVARSFILE="$TFVARSFILE/terraform.tfvars";fi
    if [ ! -f $TFVARSFILE ]; then 
        echo "ERROR: File '$TFVARSFILE' doesn't exist" | tee -a $logfile
        cleanUp 1
    fi
fi
echo TFVARSFILE: $TFVARSFILE >> $logfile
# Check DEPLOYPATH
if [ -z $DEPLOYPATH ]; then 
    read -p " -> Specify the path of the viya \$deploy directory ($(pwd)): " DEPLOYPATH
    DEPLOYPATH="${DEPLOYPATH/#\~/$HOME}"
    if [ -z $DEPLOYPATH ]; then DEPLOYPATH=$(pwd); fi
fi
if [ $DEPLOYPATH != 'unavailable' ];then 
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
    touch $OUTPATH/T${TRACKNUMBER}.tgz 2>> $logfile
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to write output file '$OUTPATH/T${TRACKNUMBER}.tgz'." | tee -a $logfile
        cleanUp 1
    fi
fi

namespaces=('kube-system')
# Look for Viya namespaces
echo 'DEBUG: Looking for Viya namespaces' >> $logfile
viyans=($($KUBECTLCMD get cm --all-namespaces 2>> $logfile | grep sas-deployment-metadata | awk '{print $1}' | sort | uniq))
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
    done
    if [ $hasViya == false ]; then
        echo "WARNING: No Viya deployments were found in any of the namespaces provided" | tee -a $logfile
        echo "WARNING: The script will continue capturing information from the namespaces provided and Viya related namespaces" | tee -a $logfile
    fi
    namespaces+=($(echo $USER_NS | tr ',' ' '))
fi

# Check if the viya4-deployment project was used
if [ -z $ANSIBLEVARSFILE ]; then 
    if $KUBECTLCMD get cm -n $USER_NS sas-deployment-buildinfo > /dev/null 2>&1; then 
        read -p " -> The viya4-deployment project was used to deploy this environment. Specify the path of the "ansible-vars.yaml" file that was used (leave blank if not known): " ANSIBLEVARSFILE
        ANSIBLEVARSFILE="${ANSIBLEVARSFILE/#\~/$HOME}"
    fi
fi
if [ ! -z $ANSIBLEVARSFILE ]; then 
    ANSIBLEVARSFILE=$(realpath $ANSIBLEVARSFILE 2> /dev/null)
    if [ -d $ANSIBLEVARSFILE ]; then ANSIBLEVARSFILE="$ANSIBLEVARSFILE/ansible-vars.yaml";fi
    if [ ! -f $ANSIBLEVARSFILE ]; then 
        echo "ERROR: File '$ANSIBLEVARSFILE' doesn't exist" | tee -a $logfile
        cleanUp 1
    fi
fi
echo ANSIBLEVARSFILE: $ANSIBLEVARSFILE >> $logfile

function addPod {
    for pod in $@; do
        if [ -z podCount ];then podCount=0;fi
        podList[$podCount]="$pod"
        podCount=$[ $podCount + 1 ]
    done
}
function addLabelSelector {
    for label in $@; do
        if [[ ! $label =~ "=" ]]; then label="app=$label" # Default label selector key is "app"
        elif [[ ${label:0-1} = "=" ]]; then label="${label%=}"; fi # Accept keys without values as label selectors
        pods=$($KUBECTLCMD -n $namespace get pod -l "$label" --no-headers 2>> $logfile | awk '{print $1}' | tr '\n' ' ')
        addPod $pods
    done
}
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
                if [ ${file##*/} == 'consul-kvs.txt' ]; then
                    # New key
                    if [[ "${p}" =~ 'config/' ]]; then
                        isSensitive='false'
                        if [[ "${p}" =~ '-----BEGIN' || "${p}" =~ 'password=' ]]; then
                            isSensitive='true'
                            printf '%s=%s\n' "${p%%=*}" '{{ sensitive data removed }}' >> $file.parsed 2>> $logfile
                        elif [[ "${p}" =~ 'pwd=' ]] ;then
                            printf '%s%s%s\n' "${p%%pwd*}" 'pwd={{ sensitive data removed }};' "$(cut -d ';' -f2- <<< ${p##*pwd=})" >> $file.parsed 2>> $logfile
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
                elif [ ${file##*/} == 'ansible-vars.yaml' ]; then
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
function getNamespaceData {
    for namespace in ${namespaces[@]}; do
        if [ ! -d $TEMPDIR/kubernetes/$namespace ]; then
            echo "  - Collecting information from the '$namespace' namespace" | tee -a $logfile
            mkdir -p $TEMPDIR/kubernetes/$namespace
            mkdir $TEMPDIR/kubernetes/$namespace/get $TEMPDIR/kubernetes/$namespace/describe $TEMPDIR/kubernetes/$namespace/top

            # If this namespace contains a Viya deployment
            if [ $($KUBECTLCMD get cm -n $namespace 2>> $logfile | grep -c sas-deployment-metadata) -gt 0 ]; then
                # If using Cert-Manager
                if [[ "$($KUBECTLCMD -n $namespace get $($KUBECTLCMD -n $namespace get cm -o name 2>> $logfile| grep sas-certframe-user-config | tail -1) -o=jsonpath='{.data.SAS_CERTIFICATE_GENERATOR}' 2>> $logfile)" == 'cert-manager' && "${#certmgrns[@]}" -eq 0 ]]; then 
                    echo "WARNING: cert-manager configured to be used by Viya in namespace $namespace, but a cert-manager instance wasn't found in the kubernetes cluster." | tee -a $logfile
                fi

                echo "    - Getting order number" | tee -a $logfile
                $KUBECTLCMD -n $namespace get secret -l 'orchestration.sas.com/lifecycle=image' -o jsonpath={.items[0].data.username} 2>> $logfile | base64 -d > $TEMPDIR/versions/$namespace\_order.txt 2>> $logfile
                cat $TEMPDIR/versions/$namespace\_order.txt >> $logfile
                echo '' >> $logfile

                echo "    - Getting cadence information" | tee -a $logfile
                $KUBECTLCMD -n $namespace get cm $($KUBECTLCMD get cm -n $namespace 2>> $logfile | grep sas-deployment-metadata | cut -f1 -d' ') -o jsonpath='{"\n"}{.data.SAS_CADENCE_DISPLAY_NAME}{"\n"}{.data.SAS_CADENCE_RELEASE}{"\n"}' > $TEMPDIR/versions/$namespace\_cadence.txt 2>> $logfile
                cat $TEMPDIR/versions/$namespace\_cadence.txt >> $logfile

                # Collect logs from pods in PODLOGS variable
                addLabelSelector $(echo $PODLOGS | tr ',' ' ')
                # Collect logs from Not Ready pods
                notreadylist=$($KUBECTLCMD -n $namespace get pod --no-headers 2>> $logfile | grep -v '1/1\|2/2\|3/3\|4/4\|5/5\|6/6\|7/7\|8/8\|9/9\|Completed' | awk '{print $1}' | tr '\n' ' ')

                addPod $notreadylist
                # Collect logs from upper pods (using same rules as start-sequencer)
                ## Level 1: Pods that should wait for Consul to be ready
                if [[ $notreadylist =~ 'sas-arke' || $notreadylist =~ 'sas-cache' || $notreadylist =~ 'sas-redis' ]]; then 
                    echo "INFO: Including logs from sas-consul-server pods, because there are dependent pods not ready..." | tee -a $logfile
                    addLabelSelector 'sas-consul-server'
                fi
                # Level 2: Pods that should wait for Consul, Arke, and Postgres
                if [[ $notreadylist =~ 'sas-logon-app' || $notreadylist =~ 'sas-identities' || $notreadylist =~ 'sas-configuration' || $notreadylist =~ 'sas-authorization' ]]; then 
                    echo "INFO: Including logs from sas-consul-server and sas-arke pods and enabling 'postgres' debugtag, because there are dependent pods not ready..." | tee -a $logfile
                    addLabelSelector 'sas-consul-server sas-arke'
                    POSTGRES=true
                fi
                # Level 3: Pods that should wait for SAS Logon
                if [[ $notreadylist =~ 'sas-app-registry' || $notreadylist =~ 'sas-types' || $notreadylist =~ 'sas-transformations' || $notreadylist =~ 'sas-relationships' || \
                    $notreadylist =~ 'sas-preferences' || $notreadylist =~ 'sas-folders' || $notreadylist =~ 'sas-files' || $notreadylist =~ 'sas-cas-administration' || \
                    $notreadylist =~ 'sas-launcher' || $notreadylist =~ 'sas-feature-flags' || $notreadylist =~ 'sas-audit' || $notreadylist =~ 'sas-credentials' || \
                    $notreadylist =~ 'sas-model-publish' || $notreadylist =~ 'sas-forecasting-pipelines' || $notreadylist =~ 'sas-localization' || \
                    $notreadylist =~ 'sas-cas-operator' || $notreadylist =~ 'sas-app-registry' || $notreadylist =~ 'sas-types' || $notreadylist =~ 'sas-transformations' || \
                    $notreadylist =~ 'sas-relationships' || $notreadylist =~ 'sas-preferences' || $notreadylist =~ 'sas-folders' || $notreadylist =~ 'sas-files' || \
                    $notreadylist =~ 'sas-cas-administration' || $notreadylist =~ 'sas-launcher' || $notreadylist =~ 'sas-feature-flags' || $notreadylist =~ 'sas-audit' || \
                    $notreadylist =~ 'sas-credentials' || $notreadylist =~ 'sas-model-publish' || $notreadylist =~ 'sas-forecasting-pipelines' || \
                    $notreadylist =~ 'sas-localization' || $notreadylist =~ 'sas-cas-operator' ]]; then 
                    echo "INFO: Including logs from sas-logon-app pod, because there are dependent pods not ready..." | tee -a $logfile
                    addLabelSelector 'sas-logon-app'
                fi

                if [[ "$CAS" = true || $notreadylist =~ 'sas-cas-' ]]; then
                    echo "    - Getting cas information" | tee -a $logfile
                    addLabelSelector "sas-cas-control" "sas-cas-operator" "app.kubernetes.io/name=sas-cas-server"
                fi
                if [[ "$CONFIG" = true ]]; then
                    echo "    - Dumping consul config" | tee -a $logfile
                    $KUBECTLCMD -n $namespace exec -it sas-rabbitmq-server-0 -c sas-rabbitmq-server -- /opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse > $TEMPDIR/kubernetes/$namespace/consul-kvs.txt 2>> $logfile
                    if [ $? -ne 0 ]; then $KUBECTLCMD -n $namespace exec -it sas-rabbitmq-server-1 -c sas-rabbitmq-server -- /opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse > $TEMPDIR/kubernetes/$namespace/consul-kvs.txt 2>> $logfile
                        if [ $? -ne 0 ]; then $KUBECTLCMD -n $namespace exec -it sas-rabbitmq-server-2 -c sas-rabbitmq-server -- /opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse > $TEMPDIR/kubernetes/$namespace/consul-kvs.txt 2>> $logfile; fi
                    fi
                    removeSensitiveData $TEMPDIR/kubernetes/$namespace/consul-kvs.txt
                fi
                crunchynotreadylist=$($KUBECTLCMD -n $namespace get pod 2>> $logfile | grep 'sas-crunchy' | grep -v '1/1\|2/2\|3/3\|4/4\|5/5\|6/6\|7/7\|8/8\|9/9' | awk '{print $1"\\|"}' | grep -v "$($KUBECTLCMD -n $namespace get pod -l 'job-name' --no-headers 2>> $logfile | awk '{print $1}')" | cut -d '\' -f1 | tr '\n' ' ')
                if [[ "$POSTGRES" = true || $notreadylist =~ 'sas-data-server-operator' || ! -z $crunchynotreadylist ]]; then
                    mkdir -p $TEMPDIR/kubernetes/$namespace/postgres
                    echo "    - Getting postgres information" | tee -a $logfile
                    addLabelSelector "sas-data-server-operator"
                    if [ $($KUBECTLCMD get crd pgclusters.webinfdsvr.sas.com > /dev/null 2>&1;echo $?) -eq 0 ]; then
                        #Crunchy4 commands
                        for pgcluster in $($KUBECTLCMD -n $namespace get pgclusters.webinfdsvr.sas.com --no-headers 2>> $logfile | awk '{print $1}'); do
                            $KUBECTLCMD -n $namespace get pgclusters.webinfdsvr.sas.com $pgcluster -o yaml > $TEMPDIR/kubernetes/$namespace/postgres/$pgcluster-crunchy4-pgcluster.yaml 2>> $logfile
                            if [[ $pgcluster =~ 'crunchy' ]]; then 
                                $KUBECTLCMD -n $namespace get configmap $pgcluster-pgha-config -o yaml > $TEMPDIR/kubernetes/$namespace/postgres/$pgcluster-crunchy4-pgha-config.yaml 2>> $logfile
                                MASTER=$($KUBECTLCMD -n $namespace get pod -l "crunchy-pgha-scope=$pgcluster,role=master" 2>> $logfile | grep crunchy | awk '{print $1}' | tr '\n' ' ')
                                $KUBECTLCMD -n $namespace exec -it $MASTER -c database -- patronictl list > $TEMPDIR/kubernetes/$namespace/postgres/$pgcluster-crunchy4-patronictl.log 2>> $logfile
                                addLabelSelector "vendor=crunchydata"
                            fi
                        done
                    fi
                    if [ $($KUBECTLCMD get crd postgresclusters.postgres-operator.crunchydata.com > /dev/null 2>&1;echo $?) -eq 0 ]; then
                        #Crunchy5 commands
                        for pgcluster in $($KUBECTLCMD -n $namespace get postgresclusters.postgres-operator.crunchydata.com --no-headers 2>> $logfile | awk '{print $1}'); do
                            $KUBECTLCMD -n $namespace get postgresclusters.postgres-operator.crunchydata.com $pgcluster -o yaml > $TEMPDIR/kubernetes/$namespace/postgres/$pgcluster-crunchy5-pgcluster.yaml 2>> $logfile
                            if [[ $pgcluster =~ 'crunchy' ]]; then 
                                $KUBECTLCMD -n $namespace describe cm -l 'postgres-operator.crunchydata.com/cluster=sas-crunchy-platform-postgres' > $TEMPDIR/kubernetes/$namespace/postgres/$pgcluster-crunchy5-configmaps.txt 2>> $logfile
                                MASTER=$($KUBECTLCMD -n $namespace get pod -l "postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$pgcluster" 2>> $logfile | grep crunchy | awk '{print $1}' | tr '\n' ' ')
                                $KUBECTLCMD -n $namespace exec -it $MASTER -c database -- patronictl list > $TEMPDIR/kubernetes/$namespace/postgres/$pgcluster-crunchy5-patronictl.log 2>> $logfile
                                addLabelSelector "postgres-operator.crunchydata.com/cluster=$pgcluster"
                                crunchypods=$($KUBECTLCMD -n $namespace get pod 2>> $logfile | grep crunchy | awk '{print $1}' | tr '\n' ' ')
                                addPod $crunchypods
                            fi
                        done
                    fi
                fi
            else
                # Not Viya Namespace
                podList=$($KUBECTLCMD -n $namespace get pod --no-headers 2>> $logfile | awk '{print $1}')
            fi
            # Collect logs
            if [ ! -z "$podList" ]; then
                echo "    - kubectl logs" | tee -a $logfile
                mkdir $TEMPDIR/kubernetes/$namespace/logs
                for pod in ${podList[@]}; do 
                    if [ $(find $TEMPDIR/kubernetes/$namespace/logs -maxdepth 1 -name $pod* | wc -l) -eq 0 ]; then
                        echo "      - $pod" | tee -a $logfile
                        for container in $($KUBECTLCMD -n $namespace get pod $pod -o=jsonpath='{.spec.initContainers[*].name}' 2>> $logfile) $($KUBECTLCMD -n $namespace get pod $pod -o=jsonpath='{.spec.containers[*].name}' 2>> $logfile); do 
                            $KUBECTLCMD -n $namespace logs $pod $container > $TEMPDIR/kubernetes/$namespace/logs/$pod\_$container.log 2>&1
                            if [ $? -ne 0 ]; then cat $TEMPDIR/kubernetes/$namespace/logs/$pod\_$container.log >> $logfile; fi
                        done
                    fi
                done
            fi
            
            # If a pod has ever been restarted by kubernetes, try to capture its previous logs
            restartedPodList=$($KUBECTLCMD -n $namespace get pod --no-headers 2>> $logfile | awk '{if ($4 > 0) print $1}' | tr '\n' ' ')
            if [ ! -z "$restartedPodList" ]; then
                echo "    - kubectl logs --previous" | tee -a $logfile
                mkdir -p $TEMPDIR/kubernetes/$namespace/logs/previous
                for pod in $restartedPodList; do
                    echo "      - $pod" | tee -a $logfile
                    for container in $($KUBECTLCMD -n $namespace get pod $pod -o=jsonpath='{.spec.initContainers[*].name}' 2>> $logfile) $($KUBECTLCMD -n $namespace get pod $pod -o=jsonpath='{.spec.containers[*].name}' 2>> $logfile); do 
                        $KUBECTLCMD -n $namespace logs $pod $container --previous > $TEMPDIR/kubernetes/$namespace/logs/previous/$pod\_$container\_previous.log 2>&1
                        if [ $? -ne 0 ]; then cat $TEMPDIR/kubernetes/$namespace/logs/previous/$pod\_$container\_previous.log >> $logfile; fi
                    done
                done
            fi
            getobjects=(casdeployments certificaterequests certificates configmaps cronjobs daemonsets dataservers deployments distributedredisclusters endpoints espconfigs esploadbalancers esprouters espservers espupdates events horizontalpodautoscalers ingresses issuers jobs opendistroclusters persistentvolumeclaims pgclusters poddisruptionbudgets pods podtemplates postgresclusters replicasets rolebindings roles routes sasdeployments secrets securitycontextconstraints serviceaccounts services statefulsets)
            describeobjects=(casdeployments certificaterequests certificates configmaps cronjobs daemonsets dataservers deployments distributedredisclusters endpoints espconfigs esploadbalancers esprouters espservers espupdates horizontalpodautoscalers ingresses issuers jobs opendistroclusters persistentvolumeclaims pgclusters poddisruptionbudgets pods podtemplates postgresclusters replicasets rolebindings roles routes sasdeployments secrets securitycontextconstraints serviceaccounts services statefulsets)
            yamlobjects=(casdeployments sasdeployments)
            # get objects
            echo "    - kubectl get" | tee -a $logfile
            for object in ${getobjects[@]}; do
                echo "      - $object" | tee -a $logfile
                $KUBECTLCMD -n $namespace get $object -o wide > $TEMPDIR/kubernetes/$namespace/get/$object.txt 2>&1
                if [[ $? -ne 0 || $(grep 'No resources found' $TEMPDIR/kubernetes/$namespace/get/$object.txt) ]]; then cat $TEMPDIR/kubernetes/$namespace/get/$object.txt >> $logfile; fi
            done
            # describe objects
            echo "    - kubectl describe" | tee -a $logfile
            for object in ${describeobjects[@]}; do
                if [[ $(grep "No resources found\|error: the server doesn't have a resource type" $TEMPDIR/kubernetes/$namespace/get/$object.txt) ]]; then 
                    cp $TEMPDIR/kubernetes/$namespace/get/$object.txt $TEMPDIR/kubernetes/$namespace/describe/$object.txt
                else
                    echo "      - $object" | tee -a $logfile
                    if [ $object == 'replicasets' ]; then 
                        # describe only active replicasets
                        $KUBECTLCMD -n $namespace describe $object $($KUBECTLCMD -n $namespace get $object --no-headers 2>> $logfile | awk '{if ($2 > 0)print $1}' | tr '\n' ' ') > $TEMPDIR/kubernetes/$namespace/describe/$object.txt 2>&1
                    else 
                        $KUBECTLCMD -n $namespace describe $object > $TEMPDIR/kubernetes/$namespace/describe/$object.txt 2>&1
                    fi
                    if [[ $? -ne 0 ]]; then cat $TEMPDIR/kubernetes/$namespace/describe/$object.txt >> $logfile; fi
                    if [ $object == 'sasdeployments' ]; then removeSensitiveData $TEMPDIR/kubernetes/$namespace/describe/$object.txt; fi
                fi
            done
            # yaml objects
            echo "    - kubectl get -o yaml" | tee -a $logfile
            for object in ${yamlobjects[@]}; do
                if [[ ! $(grep "No resources found\|error: the server doesn't have a resource type" $TEMPDIR/kubernetes/$namespace/get/$object.txt) ]]; then
                    mkdir -p $TEMPDIR/kubernetes/$namespace/yaml/$object
                    echo "      - $object" | tee -a $logfile
                    for objectName in $($KUBECTLCMD -n $namespace get $object --no-headers --output=custom-columns=PHASE:.metadata.name 2>> $logfile); do
                        $KUBECTLCMD -n $namespace get $object $objectName -o yaml > $TEMPDIR/kubernetes/$namespace/yaml/$object/$objectName.yaml 2>&1
                        if [[ $? -ne 0 ]]; then cat $TEMPDIR/kubernetes/$namespace/yaml/$object/$objectName.yaml >> $logfile; fi
                        if [ $object == 'sasdeployments' ]; then removeSensitiveData $TEMPDIR/kubernetes/$namespace/yaml/$object/$objectName.yaml; fi
                    done
                fi
            done
            # kubectl top pods
            echo "    - kubectl top pod" | tee -a $logfile
            if [[ $isOpenShift == 'false' ]]; then
                $KUBECTLCMD -n $namespace top pod > $TEMPDIR/kubernetes/$namespace/top/pods.txt 2>> $logfile
            else
                touch $TEMPDIR/kubernetes/$namespace/top/pods.txt
            fi
            # Collect 'kviya' compatible playback file (https://gitlab.sas.com/sbralg/tools-and-scripts/-/blob/main/kviya)
            echo "    - Building kviya playback file" | tee -a $logfile
            saveTime=$(date -u +"%YD%mD%d_%HT%MT%S")
            mkdir -p $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime
            cp $TEMPDIR/kubernetes/clusterwide/get/nodes.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/getnodes.out 2>> $logfile
            cp $TEMPDIR/kubernetes/clusterwide/describe/nodes.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/nodes-describe.out 2>> $logfile
            cp $TEMPDIR/kubernetes/$namespace/get/pods.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/getpod.out 2>> $logfile
            cp $TEMPDIR/kubernetes/$namespace/get/events.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/podevents.out 2>> $logfile
            cp $TEMPDIR/kubernetes/clusterwide/top/nodes.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/nodesTop.out 2>> $logfile
            cp $TEMPDIR/kubernetes/$namespace/top/pods.txt $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime/podsTop.out 2>> $logfile
            tar -czf $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime.tgz --directory=$TEMPDIR/kubernetes/$namespace/.kviya $saveTime 2>> $logfile
            rm -rf $TEMPDIR/kubernetes/$namespace/.kviya/$saveTime 2>> $logfile

            unset podCount podList
        fi
    done
}

TEMPDIR=$(mktemp -d -p $OUTPATH)
mkdir $TEMPDIR/versions

echo -e "\nINFO: Capturing environment information...\n" | tee -a $logfile

echo "  - Kubernetes and Kustomize versions" | tee -a $logfile
$KUBECTLCMD version --short > $TEMPDIR/versions/kubernetes.txt 2>> $logfile
cat $TEMPDIR/versions/kubernetes.txt >> $logfile
kustomize version --short > $TEMPDIR/versions/kustomize.txt 2>> $logfile
cat $TEMPDIR/versions/kustomize.txt >> $logfile

# Look for ingress-nginx namespaces
echo 'DEBUG: Looking for Nginx Ingress Controller namespaces' >> $logfile
ingressns=($($KUBECTLCMD get deploy -l 'app.kubernetes.io/name=ingress-nginx' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' 2>> $logfile | sort 2>> $logfile | uniq 2>> $logfile))
if [ ${#ingressns[@]} -gt 0 ]; then
    if [ ${#ingressns[@]} -gt 1 ]; then
        echo "WARNING: Multiple Nginx Ingress Controller instances were found in the current kubernetes cluster." | tee -a $logfile
    fi
    for NGINX_NS in ${ingressns[@]}; do
        echo NGINX_NS: $NGINX_NS >> $logfile
        echo "  - nginx-ingress version" | tee -a $logfile
        $KUBECTLCMD -n $NGINX_NS get deploy -l 'app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller' -o jsonpath='{.items[0].spec.template.spec.containers[].image}' > $TEMPDIR/versions/$NGINX_NS\_nginx-ingress-version.txt 2>> $logfile
        cat $TEMPDIR/versions/$NGINX_NS\_nginx-ingress-version.txt >> $logfile
        echo '' >> $logfile
    done
    namespaces+=(${ingressns[@]})
else
    echo "WARNING: An Nginx Ingress Controller instance wasn't found in the current kubernetes cluster." | tee -a $logfile
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
        $KUBECTLCMD -n $CERTMGR_NS get deploy -l 'app.kubernetes.io/name=cert-manager,app.kubernetes.io/component=controller' -o jsonpath='{.items[0].spec.template.spec.containers[].image}' > $TEMPDIR/versions/$CERTMGR_NS\_cert-manager-version.txt 2>> $logfile
        cat $TEMPDIR/versions/$CERTMGR_NS\_cert-manager-version.txt >> $logfile
        echo '' >> $logfile
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
            $KUBECTLCMD -n $OCPCERTUTILS_NS get deploy cert-utils-operator-controller-manager -o jsonpath='{.spec.template.spec.containers[].image}' > $TEMPDIR/versions/$OCPCERTUTILS_NS\_ocp-cert-utils-operator-version.txt 2>> $logfile
            cat $TEMPDIR/versions/$OCPCERTUTILS_NS\_ocp-cert-utils-operator-version.txt >> $logfile
            echo '' >> $logfile
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
        $KUBECTLCMD -n $NFSPROVISIONER_NS get deploy -l 'app=nfs-subdir-external-provisioner' -o jsonpath='{.items[0].spec.template.spec.containers[].image}' > $TEMPDIR/versions/$NFSPROVISIONER_NS\_nfs-provisioner-version.txt 2>> $logfile
        cat $TEMPDIR/versions/$NFSPROVISIONER_NS\_nfs-provisioner-version.txt >> $logfile
        echo '' >> $logfile
    done
    namespaces+=(${nfsprovisionerns[@]})
fi
# Look for sasoperator namespaces
echo 'DEBUG: Looking for SAS Deployment Operator namespaces' >> $logfile
sasoperatorns=($($KUBECTLCMD get deploy -l 'app.kubernetes.io/name=sas-deployment-operator' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [ ${#sasoperatorns[@]} -gt 0 ]; then
    namespaces+=(${sasoperatorns[@]})
    for SASOPERATOR_NS in ${sasoperatorns[@]}; do
        echo -e "SASOPERATOR_NS: $SASOPERATOR_NS" > $TEMPDIR/versions/$SASOPERATOR_NS\_sas-deployment-operator-version.txt
        echo "  - SAS Deployment Operator and sas-orchestration image versions" | tee -a $logfile
        # Check sasoperator mode
        if [[ $($KUBECTLCMD -n $SASOPERATOR_NS get deploy -l 'app.kubernetes.io/name=sas-deployment-operator' -o jsonpath='{.items[0].spec.template.spec.containers[].env[1].valueFrom}' 2>> $logfile) == '' ]]; then 
            echo -e "SASOPERATOR MODE: Cluster-Wide" >> $TEMPDIR/versions/$SASOPERATOR_NS\_sas-deployment-operator-version.txt
        else
            echo -e "SASOPERATOR MODE: Namespace" >> $TEMPDIR/versions/$SASOPERATOR_NS\_sas-deployment-operator-version.txt
        fi
        $KUBECTLCMD -n $SASOPERATOR_NS get deploy -l 'app.kubernetes.io/name=sas-deployment-operator' -o jsonpath='{.items[0].spec.template.spec.containers[].image}' >> $TEMPDIR/versions/$SASOPERATOR_NS\_sas-deployment-operator-version.txt 2>> $logfile
        cat $TEMPDIR/versions/$SASOPERATOR_NS\_sas-deployment-operator-version.txt >> $logfile
        echo '' >> $logfile
    done
    docker image ls 2>> $logfile | grep $(docker image ls 2>> $logfile | grep '^sas-orchestration' | awk '{print $3}') > $TEMPDIR/versions/sas-orchestration-docker-image-version.txt
    cat $TEMPDIR/versions/sas-orchestration-docker-image-version.txt >> $logfile
fi

# Look for Logging and Monitoring namespaces
echo 'DEBUG: Looking for Logging namespaces' >> $logfile
loggingns=($($KUBECTLCMD get deploy -l 'v4m.sas.com/name=viya4-monitoring-kubernetes' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [[ ${#loggingns[@]} -gt 0 ]]; then 
    echo -e "LOGGING_NS: ${loggingns[@]}" >> $logfile
    namespaces+=(${loggingns[@]})
fi
echo 'DEBUG: Looking for Monitoring namespaces' >> $logfile
monitoringns=($($KUBECTLCMD get deploy -l 'sas.com/monitoring-base=kube-viya-monitoring' --all-namespaces --no-headers 2>> $logfile | awk '{print $1}' | sort | uniq))
if [[ ${#monitoringns[@]} -gt 0 ]]; then 
    echo -e "MONITORING_NS: ${monitoringns[@]}" >> $logfile
    namespaces+=(${monitoringns[@]})
fi

# get iac-dac-files
if [[ ! -z $TFVARSFILE || ! -z $ANSIBLEVARSFILE ]]; then
    echo "  - Collecting iac-dac information" | tee -a $logfile
    mkdir $TEMPDIR/iac-dac-files
    if [[ ! -z $TFVARSFILE ]]; then cp $TFVARSFILE $TEMPDIR/iac-dac-files/terraform.tfvars; fi
    if [[ ! -z $ANSIBLEVARSFILE ]]; then cp $ANSIBLEVARSFILE $TEMPDIR/iac-dac-files/ansible-vars.yaml; fi
    removeSensitiveData $TEMPDIR/iac-dac-files/terraform.tfvars
    removeSensitiveData $TEMPDIR/iac-dac-files/ansible-vars.yaml
fi

echo "  - Collecting cluster wide information" | tee -a $logfile
clusterobjects=(clusterissuers clusterrolebindings clusterroles customresourcedefinitions namespaces nodes persistentvolumes storageclasses)

# get cluster objects
echo "    - kubectl get" | tee -a $logfile
mkdir -p $TEMPDIR/kubernetes/clusterwide/get
for object in ${clusterobjects[@]}; do
    echo "      - $object" | tee -a $logfile
    $KUBECTLCMD get $object -o wide > $TEMPDIR/kubernetes/clusterwide/get/$object.txt 2>&1
    if [[ $? -ne 0 || $(grep "No resources found\|error: the server doesn't have a resource type" $TEMPDIR/kubernetes/clusterwide/get/$object.txt) ]]; then cat $TEMPDIR/kubernetes/clusterwide/get/$object.txt >> $logfile; fi
done
# describe cluster objects
echo "    - kubectl describe" | tee -a $logfile
mkdir -p $TEMPDIR/kubernetes/clusterwide/describe
for object in ${clusterobjects[@]}; do
    if [[ $(grep "No resources found\|error: the server doesn't have a resource type" $TEMPDIR/kubernetes/clusterwide/get/$object.txt) ]]; then 
        cp $TEMPDIR/kubernetes/clusterwide/get/$object.txt $TEMPDIR/kubernetes/clusterwide/describe/$object.txt >> $logfile
    else
        echo "      - $object" | tee -a $logfile
        $KUBECTLCMD describe $object > $TEMPDIR/kubernetes/clusterwide/describe/$object.txt 2>&1
        if [[ $? -ne 0 ]]; then cat $TEMPDIR/kubernetes/clusterwide/describe/$object.txt >> $logfile; fi
    fi
done

# kubectl top nodes
echo "    - kubectl top nodes" | tee -a $logfile
mkdir -p $TEMPDIR/kubernetes/clusterwide/top
if [[ $isOpenShift == 'false' ]]; then
    $KUBECTLCMD top node > $TEMPDIR/kubernetes/clusterwide/top/nodes.txt 2>> $logfile
else
    touch $TEMPDIR/kubernetes/clusterwide/top/nodes.txt
fi

# Collect information from selected namespaces
getNamespaceData

# Collect deployment assets
if [ $DEPLOYPATH != 'unavailable' ]; then
    echo "  - Collecting deployment assets" | tee -a $logfile
    mkdir $TEMPDIR/assets 2>> $logfile
    cd $DEPLOYPATH 2>> $logfile
    find . -path ./sas-bases -prune -false -o -name "*.yaml" -exec tar -rf $TEMPDIR/assets/assets.tar {} \; 2>> $logfile
    tar xf $TEMPDIR/assets/assets.tar --directory $TEMPDIR/assets 2>> $logfile
    rm -rf $TEMPDIR/assets/assets.tar 2>> $logfile
    removeSensitiveData $(find $TEMPDIR/assets -type f)
fi

cp $logfile $TEMPDIR
tar -czf $OUTPATH/T${TRACKNUMBER}.tgz --directory=$TEMPDIR .
if [ $? -eq 0 ]; then
    if [ $SASTSDRIVE == 'true' ]; then
        echo -e "\nDone! File '$OUTPATH/T${TRACKNUMBER}.tgz' was successfully created." | tee -a $logfile
        # use an sftp batch file since the user password is expected from stdin
        cat > $TEMPDIR/SASTSDrive.batch <<< "put $OUTPATH/T${TRACKNUMBER}.tgz $TRACKNUMBER"
        echo -e "\nINFO: Performing SASTSDrive login. Use only an email that was authorized by SAS Tech Support for the track\n" | tee -a $logfile
        read -p " -> SAS Profile Email: " EMAIL
        echo '' | tee -a $logfile
        sftp -oPubkeyAuthentication=no -oPasswordAuthentication=no -oNumberOfPasswordPrompts=2 -oConnectTimeout=1 -oBatchMode=no -b $TEMPDIR/SASTSDrive.batch "${EMAIL}"@sft.sas.com > /dev/null 2>> $logfile
        if [ $? -ne 0 ]; then 
            echo -e "\nERROR: Failed to send the '$OUTPATH/T${TRACKNUMBER}.tgz' file to SASTSDrive through sftp. Will not retry." | tee -a $logfile
            echo -e "\nSend the '$OUTPATH/T${TRACKNUMBER}.tgz' file to SAS Tech Support using a browser (https://support.sas.com/kb/65/014.html#upload) or through the track.\n" | tee -a $logfile
            cleanUp 1
        else 
            echo -e "\nDone! File successfully sent to SASTSDrive.\n" | tee -a $logfile
            cleanUp 0
        fi
    else
        echo -e "\nDone! File '$OUTPATH/T${TRACKNUMBER}.tgz' was successfully created. Send it to SAS Tech Support.\n" | tee -a $logfile
        cleanUp 0
    fi
else
    echo "ERROR: Failed to save output file '$OUTPATH/T${TRACKNUMBER}.tgz'." | tee -a $logfile
    cleanUp 1
fi