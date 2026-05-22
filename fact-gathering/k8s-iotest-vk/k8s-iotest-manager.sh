#!/bin/bash
# This script creates the resources required to perform IO tests against nodes from a Viya 4 environment.
# Date: 16APR2025
#
# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
version='k8s-iotest-manager.sh v1.2.00'

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
touch $(pwd)/k8s-iotest-manager.log > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    touch /tmp/k8s-iotest-manager.log > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Unable to create log file in '$(pwd)' or '/tmp'."
        exit 0
    else
        logfile=/tmp/k8s-iotest-manager.log
    fi
else
    logfile="$(pwd)/k8s-iotest-manager.log"
fi
debugEnabled='false'
echo -e "$version\n$(date)\n$(bash --version | head -1)\n$(uname -a)\nCommand: ${0} ${@}\n" > $logfile


scriptPath=$(dirname $(realpath -s $0))
script=$(echo $0 | rev | cut -d '/' -f1 | rev)
if [[ -L $scriptPath/$script ]]; then
    realScriptPath=$(dirname $(realpath -s $(readlink $scriptPath/$script)))
else
    realScriptPath=$scriptPath
fi
function volumeExamples {
    echo; echo "    Volume YAML Examples:"
    echo; echo "      hostPath"
    echo "          --volume 'hostPath: {path: /mnt/work, type: Directory}'"
    echo; echo "      persistentVolumeClaim"
    echo "          --volume 'persistentVolumeClaim: {claimName: myclaim}'"
    echo; echo "      nfs"
    echo "          --volume 'nfs: {server: my.nfs.server, path: /nfspath/work}'"
    echo; echo "      ephemeral"
    echo "          --volume 'ephemeral: {volumeClaimTemplate: {spec: {accessModes: [ "ReadWriteOnce" ], storageClassName: "managed-csi-premium", resources: {requests: {storage: 128Gi}}}}}"
    echo; echo "      emptyDir"
    echo "          --volume 'emptyDir: {}'"
}

function usage {
    echo Version: "$version"
    echo; echo "Usage: $script [command] [options]"
    echo;
    echo "Run IO tests against Compute or CAS Nodes in a Viya 4 environment."
    echo;
    echo "Available Commands:"
    echo "  push                    Build and push the k8s-iotest container image to a Container Registry"
    echo "  remove                  Remove K8S IO Test resources"
    echo "  report                  Show last K8S IO Test results"
    echo "  run                     Run a K8S IO Test"
    echo "  setup                   Create K8S IO Test resources"
    echo "  show                    Show current K8S IO Test configuration"

    echo;
    echo "Options:"
    echo "  -n|--namespace          (Required) Namespace where the k8s-iotest resources will be created"
    echo "  -v|--volume             (Required) A one-line YAML definition of the volume to be tested"
    echo "  -w|--workload           (Required) Workload class of the nodes that will be tested. Allowed values are 'compute', 'cas', 'cascontroller' or 'casworker'."
    echo "  -i|--containerimageurl  (Optional) Container image URL ( Example: 'mycontainerregistry.azurecr.io/k8s-iotest:v1.0.00' )"
    echo "  -u|--cruser             (Optional) Private Container Registry user"
    echo "  -p|--crpass             (Optional) Private Container Registry password"
    echo "  -s|--imagepullsecret    (Optional) Use a custom pre-existing secret as the imagePullSecret"
    echo "  -N|--nodes              (Optional) Run a K8S IO Test specifying the number of nodes that will run the test"
    echo "  -c|--custom-args        (Optional) Run a K8S IO Test using the legacy UNIX iotest.sh script, providing its arguments (e.g., --custom-args '-i 3 -s 64 -b 10240')"   
    echo "  -r|--wait               (Optional) Wait for the IO Test to complete, then display the results"
    echo "  -d|--debug              (Optional) Enables debug messages"
    volumeExamples
    echo;
    echo "Examples:"
    echo;
    echo "Build and push the k8s-iotest container image to the Container Registry. If you also specify the --volume parameter, you will be given the option to set up the K8S IO Test resources as well."
    echo "  $ $script push --containerimageurl my.cr.io/myuser/k8s-iotest:latest --cruser mycruser --crpass mycrpass --volume 'nfs: {server: myserver, path: /nfs/export}'"
    echo;
    echo "Setup the K8S IO Test resources"
    echo "  $ $script setup --namespace k8s-iotest --workload compute --volume 'hostPath: {path: /mnt/work, type: Directory}'"
    echo;
    echo "You can also specify all required options in the command line"
    echo "  $ $script setup --namespace k8s-iotest --workload cas --containerimageurl myregistry.azurecr.io --cruser myuser --crpass mypassword --volume 'persistentVolumeClaim: {claimName: myclaim}'"
    echo;
    echo "Run a K8S IO Test and wait for the results"
    echo "  $ $script run --namespace k8s-iotest --wait"
    echo;
    echo "Run a K8S IO Test specifying the number of nodes that should be used"
    echo "  $ $script run --namespace k8s-iotest --nodes 2"
    echo;
    echo "Run a K8S IO Test using the legacy UNIX iotest.sh script"
    echo "  $ $script run --namespace k8s-iotest --custom-args '-i 3 -s 64 -b 10240'"
    echo;
    echo "                                 By: Alexandre Gomes - Apr 13, 2025"
    echo "https://gitlab.sas.com/sbralg/tools-and-scripts/-/blob/main/k8s-iotest"
}
function version {
    echo "$version"
}

function logMessage () {
    logLevel=$1
    logMessage=$2
    if [[ -z $3 ]]; then lineBreaksBefore=0; else lineBreaksBefore=$3; fi
    if [[ -z $4 ]]; then lineBreaksAfter=0; else lineBreaksAfter=$4; fi
    
    if [[ "$logLevel" != 'DEBUG' || "$logLevel" == 'DEBUG' && "$debugEnabled" == 'true' ]]; then
        for i in $(seq 1 $lineBreaksBefore); do
            echo;
        done
        if [[ -z "$logLevel" ]]; then
            ( echo "$logMessage" >&2 ) 2> >(tee -a $logfile >&2)
        else
            ( echo "$logLevel: $logMessage" >&2 ) 2> >(tee -a $logfile >&2)
        fi
        for i in $(seq 1 $lineBreaksAfter); do
            echo;
        done
    else
        return
    fi
}

# Handle ctrl+c
trap cleanUp SIGINT
function cleanUp() {
    if [ -f $logfile ]; then 
        if [[ $1 -eq 1 || -z $1 ]]; then
            if [[ -z $1 ]]; then logMessage "FATAL" "The script was terminated unexpectedly." 1; fi
            echo -e "\nScript log saved at: $logfile"
            echo -e "\nTip: You can enable debug messages by adding the --debug option."
        else rm -f $logfile; fi
    fi
    rm -rf $TEMPDIR $updatedScript #$dsYaml $sccYaml
    exit $1
}

# # Check for updates
# latestVersion=$(curl -s https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/???/k8s-iotest-manager.sh 2>> $logfile | grep '^version=' | cut -d "'" -f2)
# if [[ ! -z $latestVersion ]]; then
#     if [[ $(cut -d 'v' -f2 <<< $latestVersion | tr -d '.') -gt $(version | cut -d 'v' -f2 | tr -d '.') ]]; then
#         echo "WARNING: A new version is available! ($latestVersion)" | tee -a $logfile
#         read -p "WARNING: It is highly recommended to use the latest version. Do you want to update this script ($(version))? (y/n) " k
#         echo "DEBUG: Wants to update? $k" >> $logfile
#         if [ "$k" == 'y' ] || [ "$k" == 'Y' ] ; then
#             updatedScript=$(mktemp)
#             curl -s -o $updatedScript https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/???/k8s-iotest-manager.sh >> $logfile 2>&1
#             scriptPath=$(dirname $(realpath -s $0))
#             if cp $updatedScript $scriptPath/$script > /dev/null 2>> $logfile; then echo -e "INFO: Script updated successfully. Restarting...\n";rm -f $updatedScript;$scriptPath/$script ${@};exit $?;else echo -e "ERROR: Script update failed!\n\nINFO: Update it manually from https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/???" | tee -a $logfile;cleanUp 1;fi
#         fi
#     fi
# fi

# Initialize variables
command=''
NAMESPACE=''
workloadClass=''
nodes=''
customArgs=''
isConfigured=''
isReady='false'
configStatus=''
podsStatus=''
iotestConfigMap='k8s-iotest-config'
iotestSecret=''
iotestVolume=''
k8sIoTestPods=()
waitForResults='false'

crImage=''
crServer=''
crUser=''
crPass=''
imagePullSecretCm=''

currentCrServer=''
currentCrImage=''
currentCrUser=''
currentCrPass=''

setCommand() {
    if [[ -z "${command}" ]]; then
      command="$1"
      shift # past argument
    else
      logMessage "ERROR" "Invalid option '$1' for the '$command' command."
      cleanUp 1
    fi
}

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    push|setup|show|remove|run|report|version)
      setCommand $1
      shift # past argument
      ;;
    -h|--help|--usage)
      usage
      cleanUp 0
      ;;
    -v|--volume)
      iotestVolume="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift # past argument
      shift # past value
      ;;
    -w|--workload)
      workloadClass="$2"
      shift # past argument
      shift # past value
      ;;
    -N|--nodes)
      nodes="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--custom-args)
      customArgs="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--containerimageurl)
      crImage="$2"
      shift # past argument
      shift # past value
      ;;
    -u|--cruser)
      crUser="$2"
      shift # past argument
      shift # past value
      ;;
    -p|--crpass)
      crPass="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--imagepullsecret)
      imagePullSecretCm="$2"
      shift # past argument
      shift # past value
      ;;
    -r|--wait)
      waitForResults='true'
      shift # past argument
      ;;
    -d|--debug)
      debugEnabled='true'
      shift # past argument
      ;;
    -*|--*)
      usage
      logMessage "ERROR" "Unknown option $1" 1
      cleanUp 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

function runCmd () {
    if [[ "$debugEnabled" == 'true' ]]; then
        logMessage "DEBUG" "Command: $*"
        "$@" 2> >(sed 's/^/DEBUG: /' | tee -a $logfile >&2)
    else
        "$@" 2> /dev/null
    fi
}

if type timeout > /dev/null 2>> $logfile; then
    timeoutCmd='timeout -s KILL'
else
    logMessage "DEBUG" "'timeout' command not available. Using custom timeout function"
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
    logMessage "ERROR" "Neither 'kubectl' or 'oc' are installed in PATH." 1
    cleanUp 1
fi
if ! runCmd $KUBECTLCMD api-resources > /dev/null; then
    logMessage "ERROR" "Error while executing '$KUBECTLCMD' commands. Make sure you're able to use '$KUBECTLCMD' against the kubernetes cluster before running this script." 1
    cleanUp 1
fi

validateVariables () {
    # Validate Namespace
    if [[ -z "${NAMESPACE}" ]]; then
        logMessage "ERROR" "A namespace wasn't provided." 1
        cleanUp 1
    elif [ $(echo "${NAMESPACE}" | grep -E '^[a-z0-9][-a-z0-9]*[a-z0-9]?$') ]; then
        if [[ ! $(runCmd "${KUBECTLCMD}" get ns | awk '{print $1}' | grep ^"${NAMESPACE}"$) ]]; then
            logMessage "ERROR" "Namespace '${NAMESPACE}' doesn't exist." 1
            cleanUp 1
        fi
    else
        logMessage "ERROR" "Namespace '${NAMESPACE}' is invalid." 1 1
        cleanUp 1
    fi

    # Validate Workload Class
    if [[ $command == 'setup' ]]; then
        if [[ -z ${workloadClass} ]]; then
            logMessage "ERROR" "A workload class wasn't provided using the -w or --workload options." 1
            cleanUp 1
        fi
        if [[ ! ${workloadClass} =~ ^(compute|cas|cascontroller|casworker)$ ]]; then
            logMessage "ERROR" "Invalid workload class '${workloadClass}'. Allowed values are 'compute', 'cas', 'cascontroller' or 'casworker'." 1
            cleanUp 1
        fi
    fi

    # Validate Volume
    if [[ -z ${iotestVolume} && $command == 'setup' ]]; then
        logMessage "ERROR" "A volume YAML definition wasn't provided." 1
        volumeExamples
        cleanUp 1
    fi

    # Validate Number of Nodes
    if [[ ! -z $nodes && $nodes -le 0 ]]; then
        logMessage "ERROR" "Number of nodes must be greater than 0." 1
        cleanUp 1
    fi

    # Validate Custom Arguments (-i -s -b)
    if [[ ! -z ${customArgs} ]]; then
        if ! grep -E '\-i [1-9]+' > /dev/null <<< $customArgs || ! grep -E '\-s [1-9]+' > /dev/null <<< $customArgs || ! grep -E '\-b [1-9]+' > /dev/null <<< $customArgs; then
            logMessage "ERROR" "All iotest.sh arguments must be provided: -i (iterations), -s (block size) and -b (blocks)." 1
            cleanUp 1
        fi
    fi
}

checkConfigMap() {
    # Check existing resources
    if runCmd $KUBECTLCMD -n ${NAMESPACE} get configmap k8s-iotest-config > /dev/null; then
        iotestConfigMap='k8s-iotest-config'
        currentCrImage=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get configmap "${iotestConfigMap}" -o jsonpath='{.data.image}')
        iotestSecret=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get configmap "${iotestConfigMap}" -o jsonpath='{.data.secret}')
        iotestVolume=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get configmap "${iotestConfigMap}" -o jsonpath='{.data.volume}')
        workloadClass=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get configmap "${iotestConfigMap}" -o jsonpath='{.data.workload}')
    else
        iotestConfigMap=''
    fi
}

checkSecret() {
    if runCmd $KUBECTLCMD -n ${NAMESPACE} get secret ${iotestSecret} > /dev/null; then
        currentCrServer=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get secret "${iotestSecret}" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths | keys[0]')
        currentCrUser=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get secret "${iotestSecret}" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths | .[].username')
        currentCrPass=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get secret "${iotestSecret}" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths | .[].password')
    fi
}
checkDaemonSet() {
    podsStatus=($(runCmd $KUBECTLCMD -n ${NAMESPACE} get pod -l app=k8s-iotest -o jsonpath={.items[*].status.containerStatuses[*].ready}))
    if [[ ${podsStatus[@]} =~ 'false' || -z ${podsStatus[@]} ]]; then
        isReady='false'
    else
        isReady='true'
        k8sIoTestPods=($(runCmd $KUBECTLCMD -n ${NAMESPACE} get pod -l app=k8s-iotest --no-headers | awk {'print $1'}))
    fi
}

checkResources() {
    checkConfigMap
    if [[ ! -z $iotestSecret ]]; then
        checkSecret
    fi
    if [[ -z "${iotestConfigMap}" ]]; then
        isConfigured='false'
        configStatus='Not Configured'
    elif [[ -z "${currentCrImage}" ]]; then
        isConfigured='false'
        configStatus="Invalid - Missing Image URL in the ${iotestConfigMap} ConfigMap"
    elif [[ "${currentCrImage}" == 'ghcr.io/sbralg/k8s-iotest:latest' ]]; then
        currentCrServer='ghcr.io'
        isConfigured='true'
        configStatus="Configured - Pulling PUBLIC container image from 'ghcr.io/sbralg/k8s-iotest:latest'"
    elif [[ -z "${iotestSecret}" ]]; then
        isConfigured='true'
        configStatus="Configured - Pulling container image from '${currentCrImage}' without authentication"
    else
        isConfigured='true'
        configStatus="Configured - Pulling container image from '${currentCrImage}' using secret '${iotestSecret}' as the imagePullSecret"
    fi
    if [[ $isConfigured == 'true' ]]; then
        checkDaemonSet
    fi
    if [[ $isReady == 'false' ]]; then
        podsStatus='Not Ready - Check the status and describe output of the 'k8s-iotest' DaemonSet and Pods'
    elif isRunning; then
        podsStatus='Running IO Test'
    else
        podsStatus='Ready'
    fi
}

showResources() {
    echo;
    echo "Current K8s Iotest configuration: " | tee -a $logfile
    echo;echo "Namespace: ${NAMESPACE}" | tee -a $logfile
    if [[ $isConfigured == 'true' ]]; then
        echo "ConfigMap: ${iotestConfigMap}" | tee -a $logfile
        if [[ ! -z $iotestSecret ]]; then
            echo "Secret: ${iotestSecret}" | tee -a $logfile
        else
            echo "Secret: No imagePullSecret is configured." | tee -a $logfile
        fi
        echo "Container Registry: ${currentCrServer}" | tee -a $logfile
        if [[ ! -z $currentCrUser ]]; then
            echo "  User: ${currentCrUser}" | tee -a $logfile
            echo "  Password: ${currentCrPass}" | tee -a $logfile
        else
            echo "  Note: Image is being pulled without authentication credentials." | tee -a $logfile
        fi
        echo "Image URL: ${currentCrImage}" | tee -a $logfile
        echo;
        if [[ ! -z $workloadClass ]]; then
            echo "Workload Class: workload.sas.com/class=${workloadClass}" | tee -a $logfile
        else
            echo "Workload Class: <missing>. Reconfiguration is required to run the test." | tee -a $logfile
        fi
        echo; echo 'Test Volume:'
        echo "    $iotestVolume" | tee -a $logfile
        echo;
        echo "K8S IO Test Pods: ${podsStatus}" | tee -a $logfile
    fi
    echo;
    echo "Configuration status: ${configStatus}" | tee -a $logfile
    echo;
}

removeResources() {
    logMessage "INFO" "Removing previous k8s-iotest resources..." 0 1
    if runCmd ${KUBECTLCMD} -n ${NAMESPACE} get configmap k8s-iotest-config > /dev/null; then
        runCmd ${KUBECTLCMD} -n ${NAMESPACE} delete configmap k8s-iotest-config
    fi
    if runCmd ${KUBECTLCMD} -n ${NAMESPACE} get secret k8s-iotest-image-pull-secret > /dev/null; then
        runCmd ${KUBECTLCMD} -n ${NAMESPACE} delete secret k8s-iotest-image-pull-secret
    fi
    if runCmd ${KUBECTLCMD} -n ${NAMESPACE} get daemonset k8s-iotest > /dev/null; then
        runCmd ${KUBECTLCMD} -n ${NAMESPACE} delete daemonset k8s-iotest
    fi
    if runCmd ${KUBECTLCMD} -n ${NAMESPACE} get serviceaccount k8s-iotest > /dev/null; then
        runCmd ${KUBECTLCMD} -n ${NAMESPACE} delete serviceaccount k8s-iotest
    fi
    if runCmd ${KUBECTLCMD} -n ${NAMESPACE} get rolebinding system:openshift:scc:k8s-iotest > /dev/null; then
        runCmd ${KUBECTLCMD} -n ${NAMESPACE} delete rolebinding system:openshift:scc:k8s-iotest
    fi
    if runCmd ${KUBECTLCMD} get clusterrole system:openshift:scc:k8s-iotest > /dev/null; then
        runCmd ${KUBECTLCMD} delete clusterrole system:openshift:scc:k8s-iotest
    fi
    if runCmd ${KUBECTLCMD} get scc k8s-iotest > /dev/null; then
        runCmd ${KUBECTLCMD} delete scc k8s-iotest
    fi
    logMessage "INFO" "The K8S IO Test resources have been successfully deleted." 1
}

buildAndPushImage() {
    if type docker > /dev/null 2>> $logfile; then
        if [[ -z ${crUser} || -z ${crPass} ]]; then
            # No authentication details were provided. Verifying if Docker is already authenticated with the container registry
            runCmd bash -c "$timeoutCmd 5 docker login ${crImage%%/*} > /dev/null 2>&1"
            if [[ $? -ne 0 ]]; then
                logMessage "ERROR" "Docker is not already authenticated to the container registry. Specify all required parameters to login, build and push the container image: --containerimageurl, --cruser, --crpass." 1
                cleanUp 1
            else
                logMessage "WARNING" "No authentication details provided, but Docker is already authenticated with the container registry. Using cached credentials." 1 1
            fi
        else
            # Validate the supplied login credentials
            echo ${crPass} | runCmd $timeoutCmd 5 docker login ${crImage%%/*} -u ${crUser} --password-stdin > /dev/null
            if [[ $? -ne 0 ]]; then
                logMessage "ERROR" "Unable to log in to the Container Registry." 1
                cleanUp 1
            else
                logMessage "INFO" "Successfully authenticated with the container registry." 1 1
            fi
        fi
        docker build --platform linux/amd64 -t ${crImage##*/} $realScriptPath
        if [[ $? -eq 0 ]]; then
            logMessage "INFO" "Docker build completed successfully." 1 1
            docker tag ${crImage##*/} ${crImage}
            docker push ${crImage}
            if [[ $? -eq 0 ]]; then
                logMessage "INFO" "The k8s-iotest image has been successfully built and pushed to the Container Registry." 1
                # Check if we already have everything we need to configure the resources.
                if [[ ! -z ${iotestVolume} && ! -z ${crUser} && ! -z ${crPass} ]]; then
                    if [[ $isConfigured == 'true' ]]; then
                        removeResources
                    fi
                    crServer=$(echo "${crImage}" | cut -d '/' -f1 | cut -d ':' -f1)
                    iotestSecret='k8s-iotest-image-pull-secret'
                    createResources
                fi
            else
                logMessage "ERROR" "Failed to push the container image." 1
            fi
        else
            logMessage "ERROR" "Failed to build the container image." 1
        fi
    else
        logMessage "ERROR" "Missing the required 'docker' command." 1
        cleanUp 1
    fi
}
createResources() {
    logMessage "INFO" "Creating k8s-iotest resources..." 0 1
    # Create ConfigMap
    if [[ -z ${iotestSecret} ]]; then
        runCmd $KUBECTLCMD -n ${NAMESPACE} create configmap k8s-iotest-config --from-literal=image="${crImage}" --from-literal=volume="${iotestVolume}" --from-literal=workload="${workloadClass}"
    else
        runCmd $KUBECTLCMD -n ${NAMESPACE} create configmap k8s-iotest-config --from-literal=image="${crImage}" --from-literal=volume="${iotestVolume}" --from-literal=workload="${workloadClass}" --from-literal=secret="${iotestSecret}"
    fi
    if [[ $? -eq 0 ]]; then
        # Validate that the ConfigMap was created as expected
        checkConfigMap
        if [[ "${currentCrImage}" != "${crImage}" ]]; then
            echo -e "\nERROR: ConfigMap validation failed (${currentCrImage} != ${crImage})" | tee -a $logfile
            cleanUp 1
        fi
    fi
    if [[ ! -z "${crUser}" && ${iotestSecret} == 'k8s-iotest-image-pull-secret' ]]; then
        # Create Secret
        runCmd $KUBECTLCMD -n ${NAMESPACE} create secret docker-registry k8s-iotest-image-pull-secret --docker-server="${crServer}" --docker-username="${crUser}" --docker-password="${crPass}"
        if [[ $? -eq 0 ]]; then
            # Validate that the secret was created as expected
            checkSecret
            if [[ -z "${currentCrServer}" ]]; then
                echo -e "\nERROR: Failed to read the current Private Container Registry server name. The secret will be deleted." | tee -a $logfile
                cleanUp 1
            elif [[ "${crServer}" != "${currentCrServer}" || "${crUser}" != "${currentCrUser}" || "${crPass}" != "${currentCrPass}" ]]; then
                echo -e "\nERROR: The secret information doesn't match the provided information. The secret will be deleted." | tee -a $logfile
                echo "Current Server: ${currentCrServer}" | tee -a $logfile
                echo "Current User: ${currentCrUser}" | tee -a $logfile
                echo "Current Password: ${currentCrPassword}" | tee -a $logfile

                unset crServer crUser crPass
                cleanUp 1
            fi
        else
            logMessage "ERROR" "Failed to create the secret." 1
            cleanUp 1
        fi
    fi

    # Get CPU and Memory Limits
    cpuLimit=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get node -l workload.sas.com/class="${workloadClass}" -o jsonpath='{.items[*].status.capacity.cpu}' | tr ' ' '\n' | sort -g | head -1)
    memoryLimit=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get node -l workload.sas.com/class="${workloadClass}" -o jsonpath='{.items[*].status.capacity.memory}' | tr ' ' '\n' | sort -g | head -1)
    # If Running in OCP, get namespace GID
    if runCmd $KUBECTLCMD api-resources | grep project.openshift.io > /dev/null 2>&1; then
        isOpenShift='true'
    else
        isOpenShift='false'
    fi
    if [[ ${isOpenShift} == 'true' ]]; then
        fsGroup=$(runCmd $KUBECTLCMD get project ${NAMESPACE} -o jsonpath="{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}" | cut -d '/' -f1)
        if [[ -z "${fsGroup}" ]]; then
            logMessage "ERROR" "Failed to retrieve the fsGroup for the '${NAMESPACE}' namespace." 1
            cleanUp 1
        fi
    fi
    if [[ ! -z $cpuLimit && ! -z $memoryLimit ]]; then
        # Create DaemonSet
        dsYaml=$(mktemp)
        cp $realScriptPath/templates/k8s-iotest-daemonset.yaml $dsYaml
        sed -i "s|{{ IMAGE }}|${currentCrImage}|g" $dsYaml
        sed -i "s|{{ CPULIMIT }}|${cpuLimit}|g" $dsYaml
        sed -i "s|{{ MEMLIMIT }}|${memoryLimit}|g" $dsYaml
        if [[ ! -z $iotestSecret ]]; then
            sed -i "s/# imagePullSecrets:/imagePullSecrets:/g" $dsYaml
            sed -i "s/{{ IMAGEPULLSECRET }}/${iotestSecret}/g" $dsYaml
        fi
        if [[ ${isOpenShift} == 'true' ]]; then
            sed -i "s/seccompProfile:/# seccompProfile:/g" $dsYaml
            sed -i "s/# fsGroup:/fsGroup:/g" $dsYaml
            sed -i "s/{{ FSGROUP }}/${fsGroup}/g" $dsYaml
        fi
        sed -i "s|{{ VOLUME }}|${iotestVolume}|g" $dsYaml
        sed -i "s|{{ WORKLOAD }}|${workloadClass}|g" $dsYaml

        if [[ ${isOpenShift} == 'true' ]]; then
            sccYaml=$(mktemp)
            cp $realScriptPath/templates/k8s-iotest-scc.yaml $sccYaml

            volumeType=$(echo $iotestVolume | cut -d ':' -f1)
            if [[ "${volumeType}" == 'hostPath' ]]; then
                sed -i "s/allowHostDirVolumePlugin: false/allowHostDirVolumePlugin: true/g" $sccYaml
            fi
            sed -i "s/{{ FSGROUP }}/${fsGroup}/g" $sccYaml
            sed -i "s/{{ VOLUME_TYPE }}/${volumeType}/g" $sccYaml

            runCmd $KUBECTLCMD -n ${NAMESPACE} apply -f $sccYaml
            if [[ ! $? -eq 0 ]]; then
                logMessage "ERROR" "Failed to create the SCC." 1
                cleanUp 1
            fi
            runCmd $KUBECTLCMD -n ${NAMESPACE} adm policy add-scc-to-user k8s-iotest -z k8s-iotest
        fi
        runCmd $KUBECTLCMD -n ${NAMESPACE} apply -f $dsYaml
        if [[ ! $? -eq 0 ]]; then
            logMessage "ERROR" "Failed to create the DaemonSet." 1
            cleanUp 1
        fi
        logMessage "INFO" "The K8S IO Test resources have been successfully created." 1
    else
        logMessage "ERROR" "Unable to retrieve CPU and memory capacity from ${workloadClass} nodes." 1
    fi
}

setupResources () {
    # Check if an imagePullSecret ConfigMap was provided
    if [[ -z "${imagePullSecretCm}" ]]; then
        # Check if this is a Viya namespace and if it is using a Private Container Registry
        inputCm=($(runCmd $KUBECTLCMD -n ${NAMESPACE} get cm --no-headers | grep '^input-' | awk '{print $1}'))
        if [[ -z "${inputCm}" ]]; then
            logMessage "DEBUG" "A Viya environment wasn't detected in the "${NAMESPACE}" namespace."
        elif [[ "${#inputCm[@]}" -gt 1 ]]; then
            logMessage "DEBUG" "Multiple 'input' ConfigMap were found. Unable to determine what container registry is being used for the Viya environment."
        else
            imageRegistry=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get cm ${inputCm} -o jsonpath='{.data.IMAGE_REGISTRY}')
        fi

        if [[ ! -z "${imageRegistry}" && "${imageRegistry}" != 'cr.sas.com' ]]; then
            # Using Private CR
            logMessage "DEBUG" "The '${NAMESPACE}' namespace has a Viya environment and is currently using a Private Container Registry."
            read -p " -> Was the k8s-iotest container imaged pushed to the same Private Container Registry? (yes/no): " userInput
            logMessage "DEBUG" "User input: $userInput"
            if [[ "${userInput}" == 'yes' ]]; then
                # Read the server name from the secret
                sasImagePullSecretCm=($(runCmd $KUBECTLCMD -n ${NAMESPACE} get secret --no-headers | grep 'sas-image-pull-secrets' | awk '{print $1}'))
                if [[ -z "${sasImagePullSecretCm}" ]]; then
                    logMessage "DEBUG" "An 'sas-image-pull-secrets' ConfigMap wasn't found. An imagePullSecret won't be used."
                elif [[ "${#inputCm[@]}" -gt 1 ]]; then
                    logMessage "ERROR" "Multiple 'sas-image-pull-secrets' ConfigMap were found. Unable to determine what imagePullSecret should be used." 1
                    cleanUp 1
                else
                    iotestSecret=$sasImagePullSecretCm
                fi
                if [[ -z "${crImage}" ]]; then
                    read -p " -> Provide the complete URL of the 'k8s-iotest' container image: " crImage
                    logMessage "DEBUG" "User provided container image URL: $crImage"
                fi
                crServer=$(echo "${crImage}" | cut -d '/' -f1 | cut -d ':' -f1)
                if [[ "${crServer}" != "${imageRegistry}" ]]; then
                    logMessage "ERROR" "The server of the container image URL (${crServer}) doesn't match the server defined in the '${iotestSecret}' secret (${imageRegistry})." 1
                    cleanUp 1
                fi
                if [[ ! -z ${iotestSecret} ]]; then
                    logMessage "INFO" "The existing Viya imagePullSecret '${iotestSecret}' will be used to pull the k8s-iotest image."
                else
                    logMessage "INFO" "The k8s-iotest container image will be pulled from the ${imageRegistry} Container Registry with anonymous authentication as no imagePullSecret was found."
                fi
            fi
        fi
        if [[ -z "${iotestSecret}" ]]; then
            # Provide the option to create a new imagePullSecret if the CR where the k8s-iotest image was pushed requires one
            if [[ -z "${crImage}" ]]; then
                # Missing CR Information
                logMessage "INFO" "Provide the information of the private container registry to which the k8s-iotest container image was pushed:" 1 1
                read -p " -> Complete URL of the 'k8s-iotest' container image (ghcr.io/sbralg/k8s-iotest:latest): " crImage
                logMessage "DEBUG" "User provided container image URL: $crImage"
                if [[ -z $crImage ]]; then
                    logMessage "WARNING" "The K8S IO Test will use a PUBLIC container image located at 'ghcr.io/sbralg/k8s-iotest:latest'." 1
                    read -p " -> Continue? (yes/no): " userInput
                    logMessage "DEBUG" "User input: $userInput"
                    if [[ $userInput == 'yes' ]]; then
                        crImage='ghcr.io/sbralg/k8s-iotest:latest'
                        crServer='ghcr.io'
                    else
                        echo -e "\nAborting..." | tee -a $logfile
                        cleanUp 1
                    fi
                else
                    crServer=$(echo "${crImage}" | cut -d '/' -f1 | cut -d ':' -f1)
                    read -p " -> User (leave blank if authentication isn't required): " crUser
                    logMessage "DEBUG" "User provided Private Container Registry user: $crUser"
                    if [[ ! -z "${crUser}" ]]; then
                        read -r -p ' -> Password: ' -s crPass
                        if [[ -z "${crPass}" ]]; then
                            logMessage "ERROR" "A password wasn't provided provided." 1
                            cleanUp 1
                        else
                            echo;
                            iotestSecret='k8s-iotest-image-pull-secret'
                        fi
                    fi
                fi
            else
                crServer=$(echo "${crImage}" | cut -d '/' -f1 | cut -d ':' -f1)
            fi
            if [[ -z "${crServer}" || ! -z "${crUser}" && -z "${crPass}" ]]; then
                unset crImage crServer crUser crPass
                logMessage "ERROR" "The Private Container Registry information wasn't provided." 1
                cleanUp 1
            elif [[ ! -z "${crUser}" ]]; then
                iotestSecret='k8s-iotest-image-pull-secret'
            fi
            createResources
        fi
    else
        if runCmd $KUBECTLCMD -n ${NAMESPACE} get secret "${imagePullSecretCm}"; then
            imageRegistry=$(runCmd $KUBECTLCMD -n ${NAMESPACE} get cm "{$imagePullSecretCm}" -o jsonpath='{.data.IMAGE_REGISTRY}')
            if [[ -z "${crImage}" ]]; then
                read -p " -> Provide the complete URL of the 'k8s-iotest' container image: " crImage
                logMessage "DEBUG" "User provided container image URL: $crImage"
            fi
            crServer=$(echo "${crImage}" | cut -d '/' -f1 | cut -d ':' -f1)
            if [[ "${crServer}" != "${imageRegistry}" ]]; then
                logMessage "ERROR" "The server name of the container image URL (${crServer}) doesn't match the server name defined in the '${imagePullSecretCm}' secret (${imageRegistry})." 1
                cleanUp 1
            else
                iotestSecret=${imagePullSecretCm}
                logMessage "INFO" "The imagePullSecret '${imagePullSecretCm}' will be used to pull the k8s-iotest image."
                createResources
            fi
        else
            logMessage "ERROR" "A secret '${imagePullSecretCm}' doesn't exist in the '${NAMESPACE}' namespace." 1
            cleanUp 1
        fi
    fi
}
isRunning() {
    activePods=()
    for pod in ${k8sIoTestPods[@]}; do
        if [[ $(runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- ps -ef | grep iotest | grep -v grep | wc -l) -gt 0 ]]; then
            activePods+=($pod)
        fi
    done
    if [[ -z ${activePods[@]} ]]; then
        return 1
    else
        return 0
    fi
}
backupOldResults() {
    resultsEpoch=0
    for pod in ${k8sIoTestPods[@]}; do
        iotestLog=$(runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- ls -tr /work | grep 'results' | tail -1)
        if [[ ! -z $iotestLog ]]; then
            epoch=$(runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- stat /work/$iotestLog -c %Y)
            if [[ $epoch > $resultsEpoch ]]; then
                resultsEpoch=$epoch
            fi
        fi
    done
    resultsDir=$(date --date="@${resultsEpoch}" +"%Y%m%d_%H%M%S")
    for pod in ${k8sIoTestPods[@]}; do
        resultsFiles=($(runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- ls -trp | grep -v '/' | tail -n +3))
        if [[ ! -z ${resultsFiles[@]} ]]; then
            runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- mkdir -p /work/results/$resultsDir
            runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- mv ${resultsFiles[@]} /work/results/$resultsDir
        fi
    done
}
runIoTest() {
    if [[ -z $nodes ]]; then
        nodes=${#k8sIoTestPods[@]}
    fi
    if [[ ${#k8sIoTestPods[@]} -ge $nodes ]]; then
        nTestPods=1
        for pod in ${k8sIoTestPods[@]}; do
            if [[ $nTestPods -le $nodes ]]; then
                logMessage "INFO" "Starting IO Test in $workloadClass node $(runCmd $KUBECTLCMD -n ${NAMESPACE} get pod $pod -o jsonpath={.spec.nodeName}) (pod: $pod)"
                if [[ -z ${customArgs} ]]; then
                    runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- k8s_iotest -t /iotest > /dev/null &
                else
                    runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- bash iotest.sh -t /iotest ${customArgs} > /dev/null &
                fi
                nTestPods=$[ $nTestPods + 1 ]
            else
                break
            fi
        done
        if [[ $waitForResults == 'true' ]]; then
            getResults
        fi
    else
        logMessage "ERROR" "The number of available $workloadClass nodes (${#k8sIoTestPods[@]}) is insufficient to match the number requested nodes ($nodes) for testing." 1
        cleanUp 1
    fi
}

getResults() {
    if isRunning; then
        logMessage "INFO" "Waiting for IO tests to finish..."
        while isRunning; do
            echo -e "\n $(date) =================="
            for pod in ${k8sIoTestPods[@]}; do
                if [[ ${activePods[@]} =~ $pod ]]; then
                    podStatus='Running IO Test'
                else
                    podStatus='Idle'
                fi
                echo -e "\n================== Node $(runCmd $KUBECTLCMD -n ${NAMESPACE} get pod $pod -o jsonpath={.spec.nodeName}) ($pod) - Status: $podStatus."
                runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- bash -c "top -bn 1 | head -3"
            done
            sleep 5
        done
    fi
    resultsFound='false'
    for pod in ${k8sIoTestPods[@]}; do
        unset iotestLog
        iotestLog=$(runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- ls -trp /work | grep -v '/' | grep 'results' | tail -1)
        if [[ ! -z $iotestLog ]]; then
            echo -e "\n================== Results from Node $(runCmd $KUBECTLCMD -n ${NAMESPACE} get pod $pod -o jsonpath={.spec.nodeName}) ($pod):" | tee -a $logfile
            runCmd $KUBECTLCMD -n ${NAMESPACE} exec $pod -c k8s-iotest -- cat /work/$iotestLog | tee -a $logfile
            resultsFound='true'
        fi
    done
    if [[ $resultsFound == 'false' ]]; then
        logMessage "INFO" "No IO test results from prior runs were found."
    fi
}
main () {
    if [[ -z $command ]]; then
        logMessage "ERROR" "Missing a command." 1
        echo "Run '$script --help' for usage." | tee -a $logfile
        cleanUp 1
    fi

    validateVariables
    checkResources
    case "$command" in
        "show")
            showResources
            cleanUp 0
        ;;
        "push")
            if [[ ! -z $crImage ]]; then
                buildAndPushImage
                cleanUp 0
            else
                logMessage "ERROR" "The --containerimageurl parameter is required to build and push the container image. If Docker is not already authenticated to the container registry, you must also provide --cruser and --crpass." 1
            fi
        ;;
        "remove")
            if [[ $isConfigured == 'true' ]]; then
                removeResources
                cleanUp 0
            else
                logMessage "ERROR" "K8S IO Test is currently not configured in the '${NAMESPACE}' namespace." 1
                cleanUp 1
            fi
        ;;
        "setup")
            if [[ $isConfigured == 'true' ]]; then
                showResources
                logMessage "ERROR" "The K8S IO Test resources are already created. To remove it, run the script with the 'remove' option."
                cleanUp 1
            else
                setupResources
                cleanUp 0
            fi
        ;;
        "run")
            if isRunning; then
                logMessage "ERROR" "An IO Test is still being executed by the following pods:" 1 1
                for pod in ${activePods[@]}; do 
                    logMessage "" "   $pod"
                done
                cleanUp 1
            fi
            backupOldResults
            if [[ $isReady == 'true' ]]; then
                runIoTest
            else
                showResources
                logMessage "ERROR" "The K8S IO Test pods are not Ready." 1
                cleanUp 1
            fi
        ;;
        "report")
            getResults
        ;;
        "version")
            version
            cleanUp 0
        ;;
    esac
}
main