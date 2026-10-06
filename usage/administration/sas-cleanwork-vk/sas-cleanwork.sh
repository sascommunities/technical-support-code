#!/bin/bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Script to remove orphaned SASWORK libraries.
# This script performs the following actions:
# - Retrieves the launcher client secret from consul
# - Obtains a SAS Logon oauth token as the launcher client
# - Evaluates any top-level WORK/SASUTIL directories (i.e. COMPUTESERVER_TMP_PATH in use):
#   - If they exceed the configured maximum age, delete them.
#   - If not, extract the hostname from the directory name and strip the suffix
#     then query the launcher service to determine if the directory is orphaned.
#   - Also removes any "results-" files over 24 hours old stored at the top level.
# - Walks the tmp subdirectory paths.
#   - For compsrv, the subdirectories are named for the compute server ID. Poll the compute service to see
#     if the compute server is still valid. If no longer valid, also remove any associated spool or run directories.
#   - For batch and connectserver, the subdirectories use the same naming convention as the top-level
#     discovery, so this uses the same process as the top-level evaluation.
#
# The transformers mount the external work path into /saswork in the pod where this script runs as well as specify 
# the maximum age for the WORK directories and provide scheduling options.
#
# When COMPUTESERVER_TMP_PATH is being used, this top-level directory will contain:
# - WORK library directories with the name format "SAS_workXXXXXXXXXXXXX_{pod_name}"
# - Output files from SAS Studio named "results-{{uuid}}.{html|lst|sas}" associated with individual
#   submissions to SAS Studio
#
# When COMPUTESERVER_TMP_PATH is not being used, this top-level directory will contain subdirectories log,run,spool, and tmp
# which contain subdirectories batch, compsrv and connectserver. Each of these contain a subdirectory called "default".
# The tmp top level directory contains WORK. In the case of the compute server, the WORK library directory is held within a 
# directory named for the compute server. For batch and connectserver, the WORK library is directly beneath the "default" directory.
#
# The compute server will also create directories under run and spool named after its server ID. The Batch Server will store debug logs 
# under the logs directory, and the connect server will create a directory under run named after its pod with a number suffix.

# Set bash options:
echo "NOTE: Setting bash options errexit, nounset, and pipefail"
# Any command with a non-zero exit code to cause the script to fail.
set -o errexit
# Any reference to an undefined variable causes the script to fail.
set -o nounset
# Any command in a pipe that returns non-zero causes that pipeline to return the same non-zero
# triggering script failure from errexit.
set -o pipefail

# Get the launcher service secret from the SAS configuration server:
echo "NOTE: Attempting to retrieve sas.launcher client secret from SAS Configuration Server."
secret=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/launcher/oauth2.client.clientSecret)

# Stop if we failed to pull the secret.
if [[ -z "$secret" ]]
    then
    echo "ERROR: Failed to pull sas.launcher client secret."
    exit 1
fi

# Get an oauth token from SAS Logon Manager
echo "NOTE: Attempting to get an oauth token from SAS Logon Manager."
if ! token=$(curl -fsS "https://sas-logon-app/SASLogon/oauth/token" \
    -H "Accept: application/json" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -u "sas.launcher:${secret}" \
    -d 'grant_type=client_credentials' | jq -er '.access_token | select(type == "string" and length > 0)'); then
    echo "ERROR: Failed to get a valid token from SASLogon."
    exit 1
fi

# Define variables
del="no"
sids=()
# To avoid leaving unparseable WORK directories indefinitely, set a maximum age for WORK directories.
maxage=${MAX_WORK_AGE:-10080}  # Maximum age in minutes

# Define a function to process an array of WORK directories.
# This expects a "sid" variable populated with directories in the form SAS_workXXXXXXXXXXXXX_{pod_name}
function wdirclean {
        
        # Break if sid is null or not a valid directory.
        if [[ -z "$sid" || ! -d "$sid" ]]; then
            echo "WARNING: Skipping invalid or empty WORK directory."
            return
        fi

        # Break if sid isn't prefixed with SAS_work or SAS_util
        if [[ "$sid" != *SAS_work* && "$sid" != *SAS_util* ]]; then
            echo "WARNING: Skipping WORK directory \"${sid}\" not prefixed with SAS_work or SAS_util."
            return
        fi

        echo "NOTE: Checking WORK directory ${sid}."

        # If the directory is older than the maximum age, we should delete it.
        if [[ $(find "$sid" -maxdepth 0 -type d -mmin "+$maxage") ]]; then
            echo "NOTE: Deleting WORK directory ${sid} older than $maxage minutes."
            rm -rf "$sid"
            del="yes"
            return
        fi

        # Here, sid would resolve to a full path (/saswork/SAS_workXXXXXXXXXXXXX_{pod_name})
        # What we want is the pod name from this, so we use parameter expansion on the variable to
        # remove everything before the last "_" character.

        podname="${sid##*_}"
        echo "NOTE: Extracted pod name ${podname} from path."

        # The "podname" we've extracted above is the end of the WORK directory path, which is a possibly truncated version of the pod name, the hostname resolve from within the pod. 
        # Truncation from pod to host name occurs when the pod name exceeds 63 characters in length.

        # The hostname could be the full pod name that includes the launcher process ID or could be truncated to the point that the launcher process ID is not present at all.

        # This truncation occurs in a few different places:
        # 1. SWO Disabled - Launcher will truncate the job name to 27 characters, then append its 36 character process ID to form the final job name it submits to Kubernetes to meet Kubernetes maximum job name length requirement.
        # -- Kubernetes needs to append its own suffix to the job name when it creates the pod. It will enforce the same maximum length of 63 characters, so will truncate the process ID from the pod name and subsequent hostname.
        # -- For example, a process ID of 4da4cf80-a9f1-450a-9fee-3441f978ebe9 might become 4da4cf80-a9f1-450a-9fee-3441f9abc12
        # 2. SWO Enabled - Launcher truncates the job name to 100 characters (99 + "-") before appending its 36 character process ID. SWO adds its job ID as a suffix to this. (e.g. -1234)
        # -- While the pod name might be 136 characters plus the job ID, the "hostname" will be truncated to 63 characters. This means the entire launcher process ID could be truncated from the WORK path as well.

        # Strip the job ID or Kubernetes suffix from the hostname if present by removing everything after the last hyphen in the hostname.
        prefix=${podname%-*}

        # Query the launcher service for a process whose uuid starts with the extracted prefix. The uuid would be the full job name passed to Kubernetes or SWO.
        echo "NOTE: Checking launcher service for processes starting with ${prefix}."
        curl -s "https://sas-launcher/launcher/processes?filter=startsWith(uuid,'${prefix}')" \
            -H "Authorization: Bearer $token" \
            -H "Accept: application/json" \
            -o "$launchtmp"

        # We now need to check our json file to see if we retrieved any results.

        proccount=$(jq '.count' "$launchtmp")
        echo "NOTE: Found $proccount processes starting with ${prefix}."

        # Possible results for this are 0, 1, null (no count attribute returned), more than 1, or a parsing error.
        # We need to handle each of these possibilities.
        case $proccount in
            # If we returned no results, this means we should be OK to delete this directory.
            0 ) echo "NOTE: Found no associated process to ${sid}. Deleting."
                rm -rf "${sid}"
                del="yes"
                ;;
            # If we found one, we need to check its state to see if it has completed and if so, delete the directory.
            1 ) 
                # Get the full launcher process ID from the output file.
                pid=$(jq -r '.items[0].id' "$launchtmp")

                echo "NOTE: Found process $pid associated with ${sid}. Checking state."

                # Retrieve the state of the process from the launcher service.
                state=$(curl -s "https://sas-launcher/launcher/processes/${pid}/state" -H "Authorization: Bearer $token")
                echo "NOTE: Process $pid state is $state."

                # If the state indicates it is not running, delete the path.
                if [[ "$state" = "completed" ]] || [[ "$state" = "failed" ]] || [[ "$state" = "canceled" ]] || [[ "$state" = "serverError" ]]
                    then
                    echo "NOTE: Process $pid state is $state. Deleting."
                    rm -rf "${sid}"
                    del="yes"
                elif [[ "$state" = "running" ]]; then
                    echo "NOTE: Process $pid state is running. Skipping."
                elif [[ "$state" != "running" ]]
                    then
                    echo "WARN: Process found in an unexpected state: $state."
                fi
                ;;
            null ) echo "NOTE: No count returned from launcher for pid prefix $prefix. Skipping."
                ;;
            * ) echo "WARN: Unexpected response received when querying launcher service on prefix $prefix. Count is $proccount. Skipping."
        esac

}

# Create a temp file to store the response from launcher when searching for a process.
echo "NOTE: Creating temporary file to store launcher service response."
launchtmp=$(mktemp)

# Because COMPUTESERVER_TMP_PATH only applies to the compute server, need to check both the top-level path
# for SAS_work directories and results files, and if there is a tmp directory present, parse through it as well.

# Pull an array of top-level SAS_work directories. -maxdepth 1 only checks in the path, -type d only returns directories.

echo "NOTE: Checking for top-level WORK directories."

# Delete top-level WORK directories older than the maximum age.
find /saswork -maxdepth 1 -type d \( -name "SAS_work*" -o -name "SAS_util*" \) -mmin "+$maxage" -print
echo "NOTE: Deleting top-level WORK directories older than $maxage minutes."
find /saswork -maxdepth 1 -type d \( -name "SAS_work*" -o -name "SAS_util*" \) -mmin "+$maxage" -exec rm -rf {} \;


mapfile -t sids < <(find /saswork -maxdepth 1 -type d \( -name "SAS_work*" -o -name "SAS_util*" \) -print)
echo "NOTE: Found ${#sids[@]} top-level WORK directories."

# Run the wdirclean function defined above for each folder.
for sid in "${sids[@]}"; do
    wdirclean
    del="no"
done

# Because COMPUTESERVER_TMP_PATH being set results in files being created at the saswork root named "results-{{uuid}}.{html|lst|sas}"
# and we have no way to match these back to a process, delete any over 24 hours old.
echo "NOTE: Checking for results files older than 24 hours in top level."
find /saswork -maxdepth 1 -type f -name "results-*" -mmin +1440 -print;
echo "NOTE: Deleting these files."
find /saswork -maxdepth 1 -type f -name "results-*" -mmin +1440 -delete;

# Now that we have handled the COMPUTESERVER_TMP_PATH condition, let's move on to processing a volume mounted to /opt/sas/viya/config/var.

# Check for the presence of a "tmp" directory in the top level of saswork. 
if [[ -d "/saswork/tmp" ]]; then
    echo "NOTE: Found tmp directory in /saswork. Checking for WORK subdirectories."
    # Loop through the three possible paths
    for dir in batch compsrv connectserver; do
        for sid in /saswork/tmp/"${dir}"/default/*; do
        # If the sid ends in "*" we didn't find any contents (no glob expansion).
            if [[ -z "${sid##*\*}" ]]; then
                echo "NOTE: No contents found in /saswork/tmp/${dir}/default/."
            else
                # Skip if the directory was created in the last 10 minutes (we could be running as a compute server is starting up)
                if [[ $(find "${sid}" -maxdepth 0 -type d -mmin -10) ]]; then
                    echo "NOTE: Directory ${sid} was created less than 10 minutes ago. Skipping."
                    continue
                fi
                # First, see if our directory is just a GUID by pulling the ID from the directory:
                pid=$(echo "${sid}" | sed -E 's/^.*([0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}).*/\1/')
                # Then testing if this is same as the full directory name.
                if [[ "$pid" == "${sid##*/}" ]]; then
                    # If so, this means the ID should be the compute server process ID
                    # Call the compute service API to see if this process still exists.
                    echo "NOTE: Subdirectory ${sid##*/} appears to be a compute server directory."
                    # If the directory exceeds the max age, delete it without checking.
                    if [[ $(find "${sid}" -maxdepth 0 -type d -mmin "+$maxage") ]]; then
                        echo "NOTE: Directory ${sid} exceeds max age of ${maxage} minutes. Deleting."
                        httpresp="404"
                    else
                        echo "NOTE: Checking with the compute service if server id ${pid} is a valid compute server."
                        httpresp=$(curl -sI "https://sas-compute/compute/servers/${pid}" --write-out "%{response_code}" -H "Authorization: Bearer $token" -o /dev/null)
                    fi

                    # If we got back a 404, delete the directory.
                    if [[ "$httpresp" = "404" ]]; then
                        echo "NOTE: Process associated with ${sid##*/} not found or completed. Deleting directory."
                        rm -rf "${sid}"

                        # Also remove any spool or run directories for the compute server ID if they exist:
                        if [[ -d "/saswork/spool/compsrv/default/${pid}" ]]; then 
                            echo "NOTE: Found associated spool directory. Deleting."
                            rm -rf "/saswork/spool/compsrv/default/${pid}"
                        fi
                        if [[ -d "/saswork/run/compsrv/default/${pid}" ]]; then 
                            echo "NOTE: Found associated run directory. Deleting."
                            rm -rf "/saswork/run/compsrv/default/${pid}"
                        fi
                    elif [[ "$httpresp" = "200" ]]; then
                        echo "NOTE: Process associated with ${sid##*/} is still valid."
                    else
                        echo "Unexpected response code when querying for ID ${sid##*/}: $httpresp"
                    fi
                else
                    # If it doesn't match then we are dealing with a SAS_work formatted directory (i.e. probably a batch or connect server)
                    # Run wdirclean to evaluate the WORK path and remove it if necessary.
                    wdirclean
                    # this sets "del" = "yes" if we deleted something, so we can check this and delete the log and run directories if they exist.
                    ## Batch Server
                    # Check for Batch log files and delete them if they exist (named SASBatchScriptDebug.uid##.timestamp.podname.log)
                    if [[ "$del" = "yes" ]] && [[ "$dir" = "batch" ]]; then
                        for batch_log in /saswork/log/batch/default/SASBatchScriptDebug.*"${sid##*_}".log; do
                            [[ -e "$batch_log" || -L "$batch_log" ]] || continue
                            echo "NOTE: Found orphaned batch server log file for ${sid##*_}. Deleting."
                            rm -f -- "$batch_log"
                        done
                    fi
                    # There are two possible formats for the batch server's run directories depending on how the batch server was launched:
                    # /saswork/run/batch/default/uid{uid}/{filesetname} or /saswork/run/batch/default/uid{uid}/job.{tempName}
                    # {tempName} is used when there is no fileset associated with the batch job, and would typically occur when using runsaslm instead of submitpgm.
                    # {tempName} includes the pod name, so we can use this to identify the correct directory to delete.
                    # {filesetname} does not include the pod name, which makes things more complicated.
                    # Check for Batch run directories and delete them if they exist (named *{podname}) -- this is the tempName format.
                    if [[ "$del" = "yes" ]] && [[ "$dir" = "batch" ]]; then
                        for batch_run_dir in /saswork/run/batch/default/*/*"${sid##*_}"; do
                            [[ -e "$batch_run_dir" || -L "$batch_run_dir" ]] || continue
                            echo "NOTE: Found orphaned batch server run directory for ${sid##*_}. Deleting."
                            rm -rf -- "$batch_run_dir"
                        done
                    fi
                    # Check for Batch run directories in the filesetname format -- this is more complex as we don't have the pod name to match against.
                    # The path /saswork/run/batch/default/*/*/SASBatchScriptDebug.log will have a line HOSTNAME={podname} which we can use to identify the correct directory to delete.
                    if [[ "$del" = "yes" ]] && [[ "$dir" = "batch" ]]; then
                        for debug_log in /saswork/run/batch/default/*/*/SASBatchScriptDebug.log; do
                            [[ -f "$debug_log" ]] || continue
                            if grep -Fxq "HOSTNAME=${sid##*_}" "$debug_log"; then
                                echo "NOTE: Found orphaned batch server run directory for ${sid##*_}. Deleting."
                                rm -rf -- "${debug_log%/SASBatchScriptDebug.log}"
                            fi
                        done
                    fi
                    ## Connect Server
                    # Check for Connect Server run directories and delete them if they exist
                    if [[ "$del" = "yes" ]] && [[ "$dir" = "connectserver" ]]; then
                        for connect_run_dir in /saswork/run/connectserver/default/*"${sid##*_}"*; do
                            [[ -e "$connect_run_dir" || -L "$connect_run_dir" ]] || continue
                            echo "NOTE: Found orphaned connect server run directory for ${sid##*_}. Deleting."
                            rm -rf -- "$connect_run_dir"
                        done
                    fi
                    # Set del back to no
                    del="no"
                fi
            fi
        done
    done
fi

# When a Batch Job is submitted with restart commands, it puts WORK into /saswork/run/batch/default/uid{uid}/{filesetname}/WORK/SAS_workXXXXXXXXXXXXX_{pod_name}
# We need to deal with this as well.
echo "NOTE: Checking for WORK directories under /saswork/run/batch/default."
mapfile -t sids < <(find /saswork/run/batch/default -maxdepth 4 -type d \( -name "SAS_work*" -o -name "SAS_util*" \) -print)
echo "NOTE: Found ${#sids[@]} WORK directories."

# Run the above defined function on each folder.
for sid in "${sids[@]}"; do
    wdirclean
    del="no"
done
rm "$launchtmp"