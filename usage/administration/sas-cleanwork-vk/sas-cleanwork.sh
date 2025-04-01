#!/bin/bash

# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Script to remove orphaned SASWORK libraries.
# This script performs the following actions:
# - Retrieves the launcher client secret from consul
# - Obtains a SAS Logon oauth token as the launcher client
# - Checks the saswork path for the presence of directory "tmp" to determine if we are 
#   setting a custom COMPUTESERVER_TMP_PATH (which will prevent the creation of tmp)
# - If COMPUTESERVER_TMP_PATH is in use, extracts part of the GUID from the WORK directory based on
#   the pod name. We do this because the pod name might not contain the launcher process ID exactly.
# - If COMPUTESERVER_TMP_PATH is not in use, it will use the directory name in tmp/compsrv/default as
#   the compute server ID, and for others behave the same as above, pulling the GUID from the directory
#   name.
# - When we have a compute server ID, we call the compute service to see if the ID is valid and if not,
#   delete the directory
# - When we have the GUID fragment, we use this to query the launcher service for any processes starting
#   with that fragment. If we find any, we check their state to see if they've completed. If we don't find
#   them or they have completed, we delete the directory.
#
# The transformers mount the external work path into /saswork in the pod where this script runs.
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
token=$(curl -s "https://sas-logon-app/SASLogon/oauth/token" \
    -H "Accept: application/json" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -u "sas.launcher:${secret}" \
    -d 'grant_type=client_credentials' | sed "s/{.*\"access_token\":\"\([^\"]*\).*}/\1/g")

# Stop if we failed to get a token
if [[ -z "$token" ]]
then
    echo "ERROR: Failed to get a valid token from SASLogon."
    exit 1
fi

# Define variables
del="no"
sids=()

# Define a function to process an array of WORK directories.
# This expects a "sid" variable populated with directories in the form SAS_workXXXXXXXXXXXXX_{pod_name}
function wdirclean {
        
        echo "NOTE: Checking WORK directory ${sid}."
        # Here, sid would resolve to a full path (/saswork/SAS_workXXXXXXXXXXXXX_{pod_name})
        # What we want is the pod name from this, so we use parameter expansion on the variable to
        # remove everything before the last "_" character.

        podname="${sid##*_}"
        echo "NOTE: Extracted pod name ${podname} from path."

        # It's possible that the pod name does contain the launcher ID if the job name (e.g. sas-compute-server)
        # is longer than 20 characters, as SAS truncates this at 26 characters, and SWO is not in use. 
        # This leads to a possible 6 character difference when Kubernetes adds its own suffix to the job name.
        # Because of this, we need to extract the characters that will match, and search for processes that match 
        # that prefix.

        prefix=$( echo "${podname}" | sed -E 's/.*([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{6}).*/\1/')
        echo "NOTE: Extracted launcher process ID prefix ${prefix} from pod name."

        # Now that we have the prefix of the launcher process ID, we need to call the launcher service to see if
        # there are any that match this prefix. We'll use the startsWith filter against /launcher/processes and
        # the token from above to do this. We'll write the output to our launchtmp temporary file.

        echo "NOTE: Checking launcher service for processes starting with ${prefix}."
        curl -s "https://sas-launcher/launcher/processes?filter=startsWith(id,'${prefix}')" \
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

# Pull an array of top-level SAS_work directories. -maxdepth only checks in the path, -type only returns directories.

echo "NOTE: Checking for top-level WORK directories."
mapfile -t sids < <(find /saswork -maxdepth 1 -type d -name "SAS_work*" -print)
echo "NOTE: Found ${#sids[@]} top-level WORK directories."

# Run the above defined function on each folder.
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
                # First, see if our directory is just a GUID by pulling the ID from the directory:
                pid=$(echo "${sid}" | sed -E 's/^.*([0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}).*/\1/')
                # Then testing if this is same as the full directory name.
                if [[ "$pid" == "${sid##*/}" ]]; then
                    # If so, this means the ID should be the compute server process ID
                    # Call the compute service API to see if this process still exists.
                    echo "NOTE: Subdirectory ${sid##*/} appears to be a compute server directory."
                    echo "NOTE: Checking with the compute service if server id ${pid} is a valid compute server."
                    httpresp=$(curl -sI "https://sas-compute/compute/servers/${pid}" --write-out "%{response_code}" -H "Authorization: Bearer $token" -o /dev/null)

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
                    # Check for Batch log files and delete them if they exist (named SASBatchScriptDebug.uid##.timestamp.podname.log)
                    if [[ "$del" = "yes" ]] && [[ "$dir" = "batch" ]] && [[ -n $(ls -A "/saswork/log/batch/default/SASBatchScriptDebug.*${sid##*_}.log" 2> /dev/null) ]]; then 
                        echo "NOTE: Found orphaned batch server log files for ${sid##*_}. Deleting."
                        rm -f "/saswork/log/batch/default/SASBatchScriptDebug.*${sid##*_}.log"; fi
                    # Check for Batch run directories and delete them if they exist (named *{podname})
                    if [[ "$del" = "yes" ]] && [[ "$dir" = "batch" ]] &&  [[ -n $(ls -A "/saswork/run/batch/default/*/*${sid##*_}" 2> /dev/null) ]]; then
                        echo "NOTE: Found orphaned batch server run directories for ${sid##*_}. Deleting."
                        rm -rf "/saswork/run/batch/default/*/*${sid##*_}"; fi
                    # Check for Connect Server run directories and delete them if they exist
                    if [[ "$del" = "yes" ]] && [[ "$dir" = "connectserver" ]] && [[ -n $(ls -A "/saswork/run/connectserver/default/*${sid##*_}*" 2> /dev/null) ]]; then 
                    echo "NOTE: Found orphaned connect server run directories for ${sid##*_}. Deleting."
                    rm -rf "/saswork/run/connectserver/default/*${sid##*_}*"; fi
                    # Set del back to no
                    del="no"
                fi
            fi
        done
    done
fi

rm "$launchtmp"