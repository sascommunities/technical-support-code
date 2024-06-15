#!/bin/bash
#
# This script extends the capabilities of the transfer and folders plugins for the sas-admin CLI utility.
# Date:  06AUG2020

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Possible iterations of command execution:

############### Validation Command Options ###############

### Import Check ###
# This set of options instructs the script to confirm child objects in a supplied path 
# in the source environment are present in the target. This confirms an import completed successfully.

# transfer.sh --impcheck --content-path /Users/sasdemo --src-profile Source --tgt-profile Target

# NOTE: This option does not function with the --endpoint option as it uses a content path to compare the source and target.

### Export Check ###
# This set of options instructs the script to check a supplied export package for missing parent objects.
# If a folder ID is supplied, it will also check to see if the package is missing any objects present in the folder.

# transfer.sh --expcheck --export-file /tmp/Users_sasdemo_2020-08-05_150000.json [--folder-id <GUID>] --src-profile Source

### Source Check ###
# This set of options checks the supplied folder for any broken memberships. For example, if a file is listed as being in a 
# folder, it will check to see if the file is accessible. If not, it can optionally delete the invalid membership.

# transfer.sh --srccheck --content-path /Users/sasdemo --src-profile Source [--delete]

# NOTE: This option does not function with the --endpoint option as it uses a content path to compare the source and export package.

### Shortcut Check ###
# This set of options check the supplied folder for all reference-type objects, which are not included in an export.

# transfer.sh --shortcutcheck --content-path /Users/sasdemo --src-profile Source 

# NOTE: This option does not function with the --endpoint option as it uses a content path to search for shortcuts.

############### Operartional Command Options ###############
### Export ###
# This set of options will create and download an export package for each folder within a supplied content path.
# After downloading successfully it will remove the package it created. Adding the srccheck option will not export packages
# if the folder has inaccessible members. Adding the expcheck option will check the package after export. If retries is set
# and the export check fails, it will try again to download the package and check again until it gets a successful export or runs
# out of attempts.

# Content path

# transfer.sh --export [--expcheck] [--srccheck] [--shortcutcheck] --src-profile Source --output-path /tmp --content-path /Users [--retries #]

# Endpoint

# transfer.sh --export [--expcheck] --src-profile Source --output-path /tmp --endpoint /reports/reports [--chunksize #]

### Import ###
# This set of options will attempt to upload and import each JSON file in a supplied import path. If expcheck is set, it will only 
# upload packages that pass the check.

# transfer.sh --import --import-path "/tmp/Export_2020-08-14_082247" [--expcheck] --tgt-profile Target

### Export and Import ###
# This set of options is the same as the export function but after successfully downloading the package it then uploads and imports it.

# Content path

# transfer.sh --export [--expcheck] [--srccheck] [--shortcutcheck] --import [--impcheck] --tgt-profile Target --src-profile Source --output-path /tmp --content-path /Users [--retries #]

# Endpoint

# transfer.sh --export [--expcheck] --import --src-profile Source --output-path /tmp --endpoint /reports/reports [--chunksize #]

############### End preamble ###############

### Usage Function Definition ###

# The "usage" function is responsible for providing information on how to use the script if it is run with invalid option combinations.

function usage {
    echo ""
    echo "Usage: transfer.sh [OPTIONS]..."
    echo "Script checks export files, performs an export of each folder in a supplied parent folder,"
    echo "optionally imports those into a target environment, and checks if a target environment has"
    echo "all content present in a source environment in a supplied folder."
    echo ""
    echo "Specify which functions you would like to perform:"
    echo "  --export            Iterate through all folders provided in --content-path or every chunksize # of objects"
    echo "                      returned by --endpoint, saving them to --output-path"
    echo "  --import            Import the files created by --export into the target environment"
    echo "  --expcheck          Check the --export-file provided for missing required objects."
    echo "                      If an --id is provided, check its contents in source are in the export package."
    echo "  --impcheck          Compare the --content-path in the source and target environments, "
    echo "                      making note of items in source that are not in target."
    echo "  --srccheck          Checks that child members of the folder supplied with --content-path are reachable."
    echo "  --shortcutcheck     Lists reference objects defined for a supplied content path."
    echo ""
    echo "  -s, --src-profile <profile-name>    Specifies the name of the profile to the source environment."
    echo "                                      This is needed for the export, expcheck and impcheck functions."
    echo "  -t, --tgt-profile <profile-name>    Specifies the name of the profile to the target environment."
    echo "                                      This is needed for the import and impcheck functions."
    echo "  -a, --admin-cli-path <path>         Specifies the path to the sas-admin binary. "
    echo "                                      Default: /opt/sas/viya/home/bin/sas-admin"
    echo "  -f, --export-file <path>            Specifies the export file to check for errors. (expcheck)"
    echo "  -i, --folder-id <id>                Specifies the folder ID to check the export file against for content (expcheck)"
    echo "  -p, --content-path <path>           Specifies the SAS Content folder to compare in the source and destination environments (impcheck)"
    echo "                                      Specifies the path to iterate when producing export files (export)"
    echo "  -o, --output-path <path>            Specifies where to save the export files when creating them (export)"
    echo "                                      Default: /tmp"
    echo "  --import-path <path>                When using --import without --export, specify a path that contains export packages for import."
    echo "  --delete                            When using --srccheck, the --delete option will remove broken references."
    echo "  -r, --retries <#>                   Specify how many times to retry exporting and downloading a package that failed the check."
    echo " --files                              Tell the script to export individual objects the content path supplied, rather than folders."
    echo " --endpoint                           Specify instead of --content-path to export all the item results of a given endpoint, e.g. /reports/reports"
    echo " --chunksize                          How many objects to include in each package when using --endpoint. Default is 10."
    echo " --include-dependencies               When exporting, adds the --include-dependencies option."
    echo " --insecure, -k                       Do not fail due to certificate validation errors."
    echo "  -h, --help                          Show this usage information."
    echo ""
}

### Script first evaluates what options have been supplied ###

# If no arguments are supplied, return the help page and terminate with a non-zero return code.
if [ "$1" = "" ]
    then 
    usage
    exit 1
fi

insec=""

# Read in the arguments provided and store them to environment variables.
while [ "$1" != "" ]
    do
    case $1 in
    -s | --src-profile )        shift
                                srcprofile=$1
                                ;;
    -t | --tgt-profile )        shift
                                tgtprofile=$1
                                ;;
    -a | --admin-cli-path )     shift
                                admincli=$1
                                ;;
    --export )                  export=1
                                ;;
    --import )                  import=1
                                ;;
    --expcheck )                expcheck=1
                                ;;
    --impcheck )                impcheck=1
                                ;;
    --srccheck )                srccheck=1
                                ;;
    --delete )                  delete=1
                                ;;
    -f | --export-file )        shift
                                expfile=$1
                                ;;
    -i | --folder-id )          shift
                                folderid=$1
                                ;;
    -p | --content-path )       shift
                                contentpath=$1
                                ;;
    -o | --output-path )        shift
                                outputpath=$1
                                ;;
    -r | --retries )            shift
                                retries=$1
                                ;;
    --import-path )             shift
                                imppath=$1
                                ;;
    --shortcutcheck )           shortcutcheck=1
                                ;;
    --files )                   files=1
                                ;;
    --endpoint )                shift
                                endpoint=$1
                                ;;
    --chunksize )               shift
                                chunksize=$1
                                ;;
    --include-dependencies )    incdepopt="-d"
                                ;;
    --insecure | -k )           insec=1
                                ;;
    -h | --help )               usage
                                exit
                                ;;
    * )                         usage
                                exit 1
    esac
    shift
done

### Operational Function Definitions ###

# Define a function "expcheck" to perform the export checker actions.
function expcheck {
    echo "NOTE: Running export checker function (--expcheck)..."
    
    # Confirm an export file to check has been set and terminate with a non-zero return code if not.
    var=expfile; varcheck
    
    # Confirm the export file provided exists.
    if [ ! -f "$expfile" ]
        then
        echo "ERROR: File $expfile does not exist."
        exit 2
    fi

    # This variable is used to decide whether to import a package. 
    # Reset it to zero prior to performin the check to accomodate for multiple iterations of the checking function.
    expfail=0

    echo "$(date +"%F %T %Z") Starting export check for file $expfile." >> "${expfile%/*}/${ename}_expchck.log"

    # Create a temporary file to store the parent folders defined in the package.
    tmpfile=$(mktemp)

    # Get the parent folders defined in the export package.
    echo "NOTE: These parent folders are defined in the export package:"
    echo ""

    # Pull the parent folders into the temporary file and then write them to stdout.
    # Because multiple objects might have the same parent, we sort this list and then return only unique entires to the file.

    jq -r '.transferDetails[].connectors[] | select(.type == "parentFolder") | (.name + " " + .uri)' < "$expfile" | sort | uniq > "$tmpfile"
    cat "$tmpfile"

    echo ""
    echo "NOTE: Checking if these parent folders are also objects to be imported."
    echo ""

    echo "$(date +"%F %T %Z") NOTE: Checking if parents of objects defined in $expfile are also objects." >> "${expfile%/*}/${ename}_expchck.log"
    
    # Create an array of the URIs of the parent folders.
    mapfile -t parentarray < <(jq -r '.transferDetails[].connectors[] | select(.type == "parentFolder") | .uri' < "$expfile" | sort | uniq )
    echo "NOTE: Found ${#parentarray[@]} parent folders."
    
    # For each parent folder URI, check to see if a "transferObject" exists for that URI, meaning the folder is an exported object in the package.
    for parent in "${parentarray[@]}"
        do
        echo "NOTE: Parent $parent defined. Checking if this is in the export package."
        
        RC=$(jq -r '.transferDetails[].transferObject.summary.links[] | select(.rel == "self") | .uri' < "$expfile" | grep "$parent")

        # If the URI is not present, throw an error and change the value of expfail variable to prevent it from being imported.
        # Also set the "fail" variable to 1 to tell the error checking function to adjust the return code for the script.
        if [ -z "$RC" ]
            then
            RC=$(grep "$parent" "$tmpfile")
            echo "ERROR: $RC is not a transfer object in the package. Package incomplete."
            echo "$(date +"%F %T %Z") ERROR: Parent $RC is not a transfer object in the package. Package incomplete." >> "${expfile%/*}/${ename}_expchck.log"
            fail=1
            expfail=1
            else
            echo "$(date +"%F %T %Z") NOTE: Parent $RC does exist as an exported object." >> "${expfile%/*}/${ename}_expchck.log"
        fi
    done

    # Delete the temporary file.
    rm "$tmpfile"

    # If the export failed the first test, return an error to stdout and skip the rest of the package validation.
    if [ "$expfail" = "1" ]
        then 
        echo "ERROR: There were parent objects missing from the export package. Try to export it again."
        echo "$(date +"%F %T %Z") ERROR: There were parent objects missing from the export package. Try to export it again." >> "${expfile%/*}/${ename}_expchck.log"
        else 
        echo "NOTE: All parent objects are present in the export package."
        echo "$(date +"%F %T %Z") NOTE: All parent objects are present in the export package." >> "${expfile%/*}/${ename}_expchck.log"

        # If a folder ID is provided, try to validate the contents of the package against the folder ID.
        # We are checking if the objects listed as members of the folder also present in the package.

        # Check if the folder is empty.
        if [ -n "$contentpath" ]
            then
            profile=$srcprofile; pathcheck
        fi

        if [ "$isnull" = "1" ]
            then
                echo "NOTE: Folder $folderid appears to be empty. Skipping folder check."
            else
            if [ -z "$folderid" ]
                then
                echo "NOTE: No folder ID was supplied. Will not check source environment to confirm all current objects are present in the package."
                echo "$(date +"%F %T %Z") NOTE: No folder ID was supplied. Will not check source environment to confirm all current objects are present in the package." >> "${expfile%/*}/${ename}_expchck.log"
                else 
                echo "NOTE: A folder ID $folderid was supplied. Checking this ID for objects not contained in the export package."
                echo "$(date +"%F %T %Z") NOTE: A folder ID $folderid was supplied. Checking this ID for objects not contained in the export package." >> "${expfile%/*}/${ename}_expchck.log"

                # Confirm the folder plugin is installed.
                plugin=folders; plugincheck
                
                # Confirm the source profile was defined.
                var=srcprofile; varcheck

                # Confirm the provided source profile is a valid profile for the CLI.
                profile=$srcprofile; profilecheck
                
                # Create an array that is all of the member IDs that are of type "child" for the supplied folder id. 
                # This omits "reference" types like history and favorites that are not exported.
                mapfile -t contentarray < <($admincli $insecopt --quiet --profile "$srcprofile" --output json folders list-members --id "$folderid" --recursive | jq -r '.items[] | select (.type == "child" ) | .uri')
                echo "NOTE: Found ${#contentarray[@]} child objects in the folder."
                # For each URI in the array, check to see if it is present as an object in the package.
                for object in "${contentarray[@]}"
                    do
                    RC=$(jq -r '.transferDetails[].transferObject.summary.links[] | select(.rel == "self") | .uri' < "$expfile" | grep "$object")
                    if [ -z "$RC" ]
                        then 
                        echo "WARN: $object is in the source folder but not the package. Package does not match contents of folder."
                        echo " Package may be out of date or export did not complete successfully."
                        echo "$(date +"%F %T %Z") WARN: $object is in the source folder but not the package. Package may be out of date." >> "${expfile%/*}/${ename}_expchck.log"

                        # Setting warn so the error checking function knows to adjust the return code of the script.
                        warn=1
                        # Set expfail to trigger a retry and prevent import of incomplete package.
                        expfail=1
                        else 
                        echo "NOTE: Object $object found in package."
                        echo "$(date +"%F %T %Z") NOTE: Source object $object found in package." >> "${expfile%/*}/${ename}_expchck.log"
                    fi
                done
            fi
        fi
    fi
    unset folderid
}

# Define a function "impcheck" to compare a supplied path between two environments. 
# This lets us confirm an import was successful, or possibly not needed.
function impcheck {
    echo "NOTE: Running import checker function (--impcheck)..."

    # Confirm the content path, source profile and target profile have been set.
    var=contentpath; varcheck
    var=srcprofile; varcheck
    var=tgtprofile; varcheck

    # Confirm the folder plugin is installed.
    plugin=folders; plugincheck
    
    # Check the profiles provided are valid for the sas-admin cli
    profile=$srcprofile; profilecheck
    pathcheck
    if [ "$isnull" = "1" ]
        then
        echo "NOTE: The source $contentpath appears to be empty."
        srcnull=1
    fi
    profile=$tgtprofile; profilecheck
    pathcheck

    if [ "$isnull" = "1" ]
        then
        echo "NOTE: The target $contentpath appears to be empty."
        tgtnull=1
    fi    

    if [ "$srcnull" = "1" ] && [ "$tgtnull" = "1" ]
        then
            echo "The source and target folder was empty. Skipping remaining checks."
        else
            if [ "$srcnull" = "1" ] || [ "$tgtnull" = "1" ]
                then 
                    echo "ERROR: Source and destination did not match, one is empty."
                    fail=1
                    impcheckfail=1
                else
                # Make a temporary file to store the output of the member listing
                tmpfile=$(mktemp)

                # Create a list of objects in the target into a text file
                echo "NOTE: Pulling recursive list of members of $contentpath from target into $tmpfile"
            
                $admincli $insecopt -p "$tgtprofile" --quiet --output json folders list-members --path "$contentpath" --recursive | jq '.items[] | select (.type == "child" ) | .name' > "$tmpfile"

               if [ ! -s "$tmpfile" ]
                   then 
                       echo "WARN: It looks like we are having trouble connecting to the folders service. Pausing for 60 seconds and retrying."
                       sleep 60
                       echo "NOTE: Attempting (again) to get a list of objects in $contentpath."
            
                      $admincli $insecopt -p "$tgtprofile" --quiet --output json folders list-members --path "$contentpath" --recursive | jq '.items[] | select (.type == "child" ) | .name' > "$tmpfile"
            RC=$?        
        fi

                # Pull a list of objects from the source into an array
                echo "NOTE: Pulling recursive list of members of $contentpath from source into an array."
                IFS=$'\n'
                mapfile -t srcarray < <($admincli $insecopt -p "$srcprofile" --output json folders list-members --path "$contentpath" --recursive | jq '.items[] | select (.type == "child" ) | .name')
                echo "NOTE: Found ${#srcarray[@]} child objects in the source path."
                # For each object in the array (source), search for it in the target's text file.
                echo "NOTE: Checking for each object present in source folder listing in the target."
                for object in "${srcarray[@]}"
                do
                    RC=$(grep "$object" "$tmpfile")
                    if [ -z "$RC" ]
                    then 
                        echo "ERROR: $object not found in destination."
                        fail=1
                        impcheckfail=1
                    fi
                done

                # Clean up temp file
                rm "$tmpfile"

                # Put a summary warning in stdout.
                if [ "$impcheckfail" = "1" ]
                    then echo "ERROR: Some objects in the source were not in the destination at the same path."
                fi
            fi
    fi
    unset srcnull
    unset tgtnull
    unset impcheckfail
}

# Define a function "export" to perform an export from the source.
# If --import is set, import them to the target.
# If --srccheck is set, do not export if source has problems.
# If --expcheck is set, check the exports after exporting them and don't import them if they fail export check.
# If --impcheck is set, compare the source and destination after performing the import.
function export {
    echo "NOTE: Running export function (--export)..."

    if  { [ -z "$contentpath" ] && [ -z "$endpoint" ]; }  || { [ -n "$contentpath" ] && [ -n "$endpoint" ]; }
        then
        echo "ERROR: Either --content-path or --endpoint must be specified to export."
        exit 1
    fi

    #var=contentpath; varcheck
    var=srcprofile; varcheck

    # If no output path is provided set it to /tmp, and confirm we can write to whatever output-path is.
    outputcheck

    # Confirm the folder plugin is installed.
    plugin=folders; plugincheck

    # Confirm the transfer plugin is installed.
    plugin=transfer; plugincheck

    # Confirm the source profile supplied is valid.
    profile=$srcprofile; profilecheck

    # If contentpath supplied, confirm it is valid and build a list of objects from it (srcarray).
    if [ -n "$contentpath" ]
        then
            pathcheck

            if [ "$isnull" = "1" ]
                then
                    echo "ERROR: Export path $contentpath appears to be empty. Stopping."
                    exit 2
            fi
            # Get the name and folder IDs of the folders in the content path supplied.
            IFS=$'\n'
            mapfile -t srcarray < <($admincli $insecopt --output json -p "$srcprofile" folders list-members --path "$contentpath" | jq -r '.items[] | (.name + " " + .uri)' )
    
            echo "NOTE: Found ${#srcarray[@]} objects in $contentpath."
    fi

    # Create a directory in the output directory to store the export
    date=$(date +%F_%H%M%S)
    exportdir="$outputpath/Export_$date"
    mkdir "$exportdir"

    # Confirm we were able to create the directory.
    if [ ! -d "$exportdir" ]
        then
        echo "ERROR: Failed to create export directory $exportdir. Do we have permission to create a directory in $outputpath?"
        exit 2
    fi

    # Write some initial information on the export to the log.
    echo "$(date +"%F %T %Z") Starting the export loop with the following settings:" >> "$exportdir/export.log"
    echo "  admincli=$admincli" >> "$exportdir/export.log"
    echo "  srcprofile=$srcprofile" >> "$exportdir/export.log"
    if [ -z "$endpoint" ]
        then
            echo "  contentpath=$contentpath" >> "$exportdir/export.log"
        else
            # Remove trailing / from the endpoint if present
            var=endpoint; varcheck
            echo "  endpoint=$endpoint" >> "$exportdir/export.log"
    fi
    echo "  outputpath=$outputpath" >> "$exportdir/export.log"

    if [ -n "$contentpath" ]
        then
    
        # Iterate through each member of the content path.
        for id in "${srcarray[@]}"
            do
            # Extract the uri (/folders/folders/<id>) from the array variable that contains both the name and URI.
            uri=${id##* }

            # Get the service endpoint for that URI (folders, files, etc.)
            svc=$(echo "$uri" | cut -f2 -d'/')

            # If it isn't a folder, don't export it (unless files option is set)
            if  { [ "$svc" = "folders" ] && [ -z "$files" ]; } || { [ "$files" = "1" ] && [ "$svc" != "folders" ]; }
                then

                    # Get the ID from the URI
                    fid=${id##*/}

                    # Get the folder name
                    fname=${id% *}

                    # If --shortcutcheck is set, get a list of shortcuts in the user's folder.
                    if [ "$shortcutcheck" = "1" ]
                        then
                            oldcontpath="$contentpath"
                            contentpath="${contentpath}/$fname"
                            getshortcuts
                            contentpath="$oldcontpath"
                    fi

                    # If --srccheck is set, perform a source check on the path prior to export.
                    if [ "$srccheck" = "1" ]
                        then                        
                            oldcontpath="$contentpath"
                            contentpath="${contentpath}/$fname"
                            olduri="$uri"
                            sourcecheck
                            contentpath="$oldcontpath"
                            uri="$olduri"
                        else
                            srccheckfail=0
                    fi

                    # Only export if source check succeeded or was not set.
                    if [ "$srccheckfail" = "0" ]
                        then
                            # Create a new variable that removes any spaces from the name of the folder.
                            fnns=${fname// /_}

                            # Define a date variable to timestamp the export name to ensure it is unique.
                            date=$(date +%F_%H%M%S)

                            # Get the name of the folder we are searching through (i.e. Users, Products), again replacing spaces.
                            topname="${contentpath##*/}"
                            topname=${topname// /_}

                            # Create an export name that is a combination of the folder we are searching, the folder we are exporting, and the timestamp.
                            ename=${topname}_${fnns}_$date

                            # Check the length of the top name plus the folder name. This, combined with the date needs to be less than 100 characters.
                            declare -i length
                            length=${#ename}
                            if [ "$length" -gt 100 ]
                                then
                                    # Compress the folder name to the first character
                                    echo "NOTE: $ename is more than 100 characters. Truncating folder name to first characters."
                                    fnns=$(echo $fnns | sed 's/\(.\)[^_]*_*/\1/g')
                                    ename=${topname}_${fnns}_$date
                                    echo "NOTE: New export name is $ename."
                            fi

                            # Create a file name that takes the export name and adds .json to it and specifies the output path as its location.
                            efname=$exportdir/$ename.json

                            # Run the export and download function to pull down the package.
                            exportdownload

                            if [ "$exportfail" = "0" ] && [ "$downfail" = "0" ]
                                then
                                    # Check if the --expcheck flag was set. If so, run the export check function against the package that was downloaded.
                                    # If not, set expfail to zero skip the validation if --import is set.
                                        if [ "$expcheck" = "1" ]
                                            then
                                            expfile=$efname
                                            folderid=$fid
                                            expcheck

                                            # If retries is set and exportcheck failed, try to download it again until it succeeds or the number of retries is consumed.
                                            if [ -n "$retries" ] && [ "$expfail" != "0" ]
                                                then
                                                # Confirm retries is a number.
                                                re='^[0-9]+$'
                                                if [[ $retries =~ $re ]]
                                                    then
                                                    i=$retries
                                                    # try for the number of retries or until export is successful.
                                                    while [[ $i -ge 0 ]] && [ "$expfail" = "1" ]
                                                        do
                                                        echo "$(date +"%F %T %Z") NOTE: Retries set to $retries. Trying to export and download again. Attempt $i." >> "$exportdir/export.log"

                                                        # Create a new name for the export file.
                                                        date=$(date +%F_%H%M%S)
                                                        ename=${topname}_${fnns}_$date
                                                        efname=$exportdir/$ename.json

                                                        # Try to download it again.

                                                        exportdownload

                                                        # If the download succeeds, check the new file.
                                                        if [ "$exportfail" = "0" ] && [ "$downfail" = "0" ]
                                                            then
                                                            expfile=$efname
                                                            expcheck
                                                        fi
                                                        # Increment the loop
                                                        i=$((i-1))
                                                    done
                                                fi

                                            else
                                            expfail=0
                                        fi

                                        # Check if --import is set. If so, check if the expcheck function set expfail to 1 indicating a problem with the package parentage.
                                        # If not, import it by calling the import function.
                                        if [ "$import" = "1" ]
                                            then
                                            if [ "$expfail" = "0" ]
                                            then uploadandimport
                                            fi
                                        fi

                                        # Check if --impcheck is set. If so, run the import check function against the source and destination for the import package's path.
                                        # When complete, reset the contentpath variable to its original value so the loop can continue as expected.
                                        
                                        if [ "$impcheck" = "1" ]
                                            then
                                            oldcontpath="$contentpath"
                                            contentpath="$contentpath/$fname"
                                            impcheck
                                            contentpath="$oldcontpath"
                                        fi
                                    fi
                                else
                                    echo "ERROR: Export or download of $uri failed. Check ${efname%/*}/export.log for details."
                                    fail=1
                            fi
                        else
                        echo "ERROR: Source checking failed. Will not export $contentpath/$fname. Use --delete option to remove inaccessible members."
                        fail=1
                    fi

                else echo "WARN: $contentpath contains object $uri that is not a folder. Skipping..."
            fi
        done
        else

            # Export based on endpoint

            # Get the base URL and access token from the profile.
            token=$(jq ".[\"${profile}\"]" ~/.sas/credentials.json | jq -r '."access-token"')
            baseurl=$(jq ".[\"${profile}\"]" ~/.sas/config.json | jq -r '."sas-endpoint"')

            # Get the first chunk of reports to export

            if [ -z "$chunksize" ]
                then
                    chunksize=10
            fi

            re='^[0-9]+$'
            if ! [[ $chunksize =~ $re ]]
                then
                    echo "ERROR: $chunksize is not an integer."
                    exit 1
            fi

            # Confirm the endpoint exists
            rc=$(curl -s -L -I "${baseurl}${endpoint}" --header 'Content-Type: application/json' --header "Authorization: Bearer $token" -o /dev/null -w "%{http_code}")
            if [ "$rc" != "200" ]
                then
                    echo "ERROR: ${baseurl}${endpoint} did not return a HTTP 200 response code. Is the endpoint correct?"
                    exit 1
            fi

            # Make a temporary file to store these objects
            content=$(mktemp)

            # Query the endpoint
            curl -s -L "${baseurl}${endpoint}?limit=${chunksize}" --header 'Content-Type: application/json' --header "Authorization: Bearer $token"  > "$content"

            # Get total qty
            count=$(jq '.count' "$content")
            if [ "$count" = "null" ]
                then
                count=$(jq '.items | length' "$content")
            fi

            if [ "$count" -le 0 ]
                then
                    echo "ERROR: Found $count ${endpoint##*/} objects."
                    exit 1
            fi

            echo "NOTE: Found $count ${endpoint##*/} objects."

            # Set an export number
            enum=1

            # Define a date variable to timestamp the export name to ensure it is unique.
            date=$(date +%F_%H%M%S)

            # Build a name for the export
            ename=${endpoint##*/}_${enum}_$date

            # Create a file name that takes the export name and adds .json to it and specifies the output path as its location.
            efname=$exportdir/$ename.json

            # Build a list of objects to be exported
            package=$(mktemp)
            mapfile -t uris < <(jq --arg endpoint "$endpoint" '$endpoint + "/" + .items[].id' "$content")
            echo "${uris[@]}" | jq -s  --arg exportname "$ename" '. as $uri | {"version": 1,"name":$exportname,"description": "Export built with transfer.sh", "items":[]}  | .items = $uri' > "$package"

            # We now have an export package file $package that can be exported with sas-admin transfer export --request @$content
            # Call the export and download function to pull it down.

            endpointexportdownload

            # If export and download was successful, import it.
            if [ "$exportfail" = "0" ] && [ "$downfail" = "0" ]
                then

                    # Check if the --expcheck flag was set. If so, run the export check function against the package that was downloaded.
                    # If not, set expfail to zero skip the validation if --import is set.
                    if [ "$expcheck" = "1" ]
                        then
                        expfile=$efname
                        expcheck

                        # If retries is set and exportcheck failed, try to download it again until it succeeds or the number of retries is consumed.
                        if [ -n "$retries" ] && [ "$expfail" != "0" ]
                            then
                            # Confirm retries is a number.
                            re='^[0-9]+$'
                            if [[ $retries =~ $re ]]
                                then
                                i=$retries
                                # try for the number of retries or until export is successful.
                                while [[ $i -ge 0 ]] && [ "$expfail" = "1" ]
                                    do
                                    echo "$(date +"%F %T %Z") NOTE: Retries set to $retries. Trying to export and download again. Attempt $i." >> "$exportdir/export.log"

                                    # Create a new name for the export file.
                                    date=$(date +%F_%H%M%S)
                                    ename=${endpoint##*/}_${enum}_$date
                                    efname=$exportdir/$ename.json

                                    # Try to download it again.

                                    endpointexportdownload

                                    # If the download succeeds, check the new file.
                                    if [ "$exportfail" = "0" ] && [ "$downfail" = "0" ]
                                        then
                                        expfile=$efname
                                        expcheck
                                    fi
                                    # Increment the loop
                                    i=$((i-1))
                                done
                            fi

                            else
                            expfail=0
                        fi
                    fi

                    # Check if --import is set. If so, check if the expcheck function set expfail to 1 indicating a problem with the package parentage.
                    # If not, import it by calling the import function.
                    if [ "$import" = "1" ] && [ "$expfail" = "0" ]
                        then uploadandimport
                    fi

                else
                echo "ERROR: Export or download of $ename package failed. Check ${efname%/*}/export.log for details."
                fail=1
                
            fi
            
            # Now we need to build and export/download packages until we run out of chunks.

            # Empty the next variable
            nexturl=

            # Check for a next link
            nexturl=$(jq -r '.links[] | select(.rel == "next")|.href' "$content")

            # While next urls exist, hit them, to rebuild $package and run endpointexportdownload for each.
            while [ -n "$nexturl" ]
                do
                    # increment enum
                    enum=$((enum+1))
                    # set a new ename
                    ename=${endpoint##*/}_${enum}_$date
                    # set a new efname
                    efname=$exportdir/$ename.json
                    # pull the contents for the next url
                    curl -k -s -L "${baseurl}${nexturl}" --header 'Content-Type: text/plain' --header "Authorization: Bearer $token" > "$content"
                    # read them into an array
                    mapfile -t uris < <(jq --arg endpoint "$endpoint" '$endpoint + "/" + .items[].id' "$content")
                    # convert to json package
                    echo "${uris[@]}" | jq -s  --arg exportname "$ename" '. as $uri | {"version": 1,"name":$exportname,"description": "Export built with transfer.sh", "items":[]}  | .items = $uri' > "$package"
                    # export and download the package
                    endpointexportdownload

                    # If export and download was successful, import it.
                    if [ "$exportfail" = "0" ] && [ "$downfail" = "0" ]
                        then

                            # Check if the --expcheck flag was set. If so, run the export check function against the package that was downloaded.
                            # If not, set expfail to zero skip the validation if --import is set.
                            if [ "$expcheck" = "1" ]
                                then
                                    expfile=$efname
                                    expcheck

                                    # If retries is set and exportcheck failed, try to download it again until it succeeds or the number of retries is consumed.
                                    if [ -n "$retries" ] && [ "$expfail" != "0" ]
                                        then
                                        # Confirm retries is a number.
                                        re='^[0-9]+$'
                                        if [[ $retries =~ $re ]]
                                            then
                                            i=$retries
                                            # try for the number of retries or until export is successful.
                                            while [[ $i -ge 0 ]] && [ "$expfail" = "1" ]
                                                do
                                                echo "$(date +"%F %T %Z") NOTE: Retries set to $retries. Trying to export and download again. Attempt $i." >> "$exportdir/export.log"

                                                # Create a new name for the export file.
                                                date=$(date +%F_%H%M%S)
                                                ename=${endpoint##*/}_${enum}_$date
                                                efname=$exportdir/$ename.json

                                                # Try to download it again.

                                                endpointexportdownload

                                                # If the download succeeds, check the new file.
                                                if [ "$exportfail" = "0" ] && [ "$downfail" = "0" ]
                                                    then
                                                    expfile=$efname
                                                    expcheck
                                                fi
                                                # Increment the loop
                                                i=$((i-1))
                                            done
                                        fi

                                        else
                                        expfail=0
                                    fi

                            fi

                            # Check if --import is set. If so, check if the expcheck function set expfail to 1 indicating a problem with the package parentage.
                            # If not, import it by calling the import function.
                            if [ "$import" = "1" ] && [ "$expfail" = "0" ]
                                then uploadandimport
                            fi

                        else
                        echo "ERROR: Export or download of $ename package failed. Check ${efname%/*}/export.log for details."
                        fail=1
                        
                    fi

                    # get the next url to repeat the process
                    nexturl=$(jq -r '.links[] | select(.rel == "next") | .href' "$content")
            done

    fi
}

# Create a function for performing an import of a supplied package.
# Needs $efname, $tgtprofile, $admincli set.
function uploadandimport {
    echo "NOTE: Running upload and import function (--import) ..."

    # Confirm a target profile is defined.
    var=tgtprofile; varcheck

    # Confirm the target profile is valid.
    profile=$tgtprofile; profilecheck

    echo "$(date +"%F %T %Z") NOTE: Attempting to upload $efname to target." >> "${efname%/*}/import.log"

    # Upload the export package to the target environment, capturing the upload ID from the output.
    impid=$($admincli $insecopt --output json -p "$tgtprofile" transfer upload --file "$efname" | jq -r '.id' )
    RC=$?
    
    # If the command is successful, attempt to import the package.
    if [ "$RC" = "0" ]
        then
        echo "NOTE: Upload appears to have been successful."
            if [ -n "$impid" ]
                then
                echo "NOTE: Upload complete. Attempting import."
                echo "$(date +"%F %T %Z") NOTE: Upload completed. ID on target $impid." >> "${efname%/*}/import.log"
                
                $admincli $insecopt --output json -p "$tgtprofile" transfer import --id "$impid"
                RC=$?

                # If the import is successful, delete the uploaded package.
                if [ "$RC" = "0" ]
                    then 
                    echo ""
                    echo "NOTE: Import complete."
                    echo "$(date +"%F %T %Z") NOTE: Import appears to have completed successfully." >> "${efname%/*}/import.log"
                    echo "NOTE: Removing imported package from the transfer service."
                    echo "$(date +"%F %T %Z") NOTE: Attempting to delete the uploaded package." >> "${efname%/*}/import.log"
                    echo "y" | $admincli $insecopt --output json -p "$tgtprofile" transfer delete --id "$impid"; RC=$?; echo ""
                    
                    # If the delete is successful, write success to stdout.
                    if [ "$RC" = "0" ]
                        then echo "NOTE: Removal complete."
                        echo "$(date +"%F %T %Z") NOTE: Successfully deleted the uploaded package." >> "${efname%/*}/import.log"
                        else
                        echo "ERROR: sas-admin CLI returned a non-zero return code for the delete attempt of transfer id $impid."
                        echo "$(date +"%F %T %Z") ERROR: sas-admin CLI returned a non-zero return code for the delete attempt of transfer id $impid." >> "${efname%/*}/import.log"
                        fail=1
                    fi
                    else 
                    echo "ERROR: sas-admin CLI returned a non-zero return code from this import."
                    echo "RC=$RC"
                    echo "$(date +"%F %T %Z") ERROR: sas-admin CLI returned a non-zero return code from this import." >> "${efname%/*}/import.log"
                    fail=1
                fi
                else 
                echo "ERROR: Upload named $ename not found in destination."
                echo "$(date +"%F %T %Z") ERROR: Upload named $ename not found in destination." >> "${efname%/*}/import.log"
                fail=1
            fi
        else
        echo "ERROR: sas-admin CLI had a non-zero return code on this attempt."
        echo "ERROR: RC=$RC"
        echo "$(date +"%F %T %Z") ERROR: sas-admin CLI had a non-zero return code attempting to upload $efname." >> "${efname%/*}/import.log"
        fail=1
    fi
}

# Define a function to create an export and download it.
# This process needs $srcprofile, $admincli, $ename, $expid, $efname, $uri already set.
# If the function is successful, the file $efname will exist.
# If the function fails because the export failed the output of the export command will be in the export directory.
function exportdownload {
    echo "NOTE: Attempting to create export package for resource $uri."
    echo "$(date +"%F %T %Z") NOTE: Attempting to create export package for resource $uri." >> "${efname%/*}/export.log"
    exportfail=0
    downfail=0
    # Create a temporary file to store output from the export command
    tmpfile=$(mktemp)

    # Export the package and capture the output to a file.
    $admincli $insecopt --output json -p "$srcprofile" transfer export "${incdepopt}" --name "$ename" --resource-uri "$uri" > "$tmpfile" 2>&1
    RC=$?

    # Check if the output is blank, suggesting we encountered an issue connecting to the service. If so, wait a minute a try again (-s means if file exists and has a size greater than 0)
    if [ ! -s "$tmpfile" ]
        then 
        echo "WARN: It looks like we are having trouble connecting to the transfer service. Pausing for 60 seconds and retrying."
        echo "$(date +"%F %T %Z") WARN: It looks like we are having trouble connecting to the transfer service. Pausing for 60 seconds and retrying." >> "${efname%/*}/export.log"
        sleep 60
        echo "NOTE: Attempting (again) to create export package for resource $uri."
        echo "$(date +"%F %T %Z") NOTE: Attempting (again) to create export package for resource $uri." >> "${efname%/*}/export.log"
        $admincli $insecopt --output json -p "$srcprofile" transfer export "${incdepopt}" --name "$ename" --resource-uri "$uri" > "$tmpfile" 2>&1
        RC=$?        
    fi

    # See if the export output reports the wait exceeded.
    timeout=$(grep -c "The wait time has been exceeded" "$tmpfile")
    if [ "$timeout" = "1" ]
    then
        echo "WARN: Export of package $ename has exceeded the timeout period. The script will continue."
        echo "$(date +"%F %T %Z") WARN: Export of package $ename - $uri has exceeded the timeout period. The package will need to be downloaded manually." >> "${efname%/*}/export.log"
        echo "$(date +"%F %T %Z") NOTE: Run sas-admin -p $srcprofile transfer list --name $ename to get the package ID so you can download it." >> "${efname%/*}/export.log"
        warn=1
        exportfail=1
        echo "NOTE: You will need to manually download/check this package after it completes."
        echo "NOTE: Run sas-admin -p $srcprofile transfer list --name $ename to get the package ID so you can download it."
    else
        # Check the output to see it has completed.
        complete=$(grep -c completed "$tmpfile")
        if [ "$RC" = "0" ] && [ "$complete" = "2" ]
            then
            # If completed, get the transfer ID returned.
            expid=$(grep -E -o '[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}' "$tmpfile")
            echo "NOTE: Export package $expid created successfully."
            rm "$tmpfile"
            echo "$(date +"%F %T %Z") NOTE: Export $ename created as $expid." >> "${efname%/*}/export.log"
            echo "NOTE: Downloading to $efname."
            echo "$(date +"%F %T %Z") NOTE: Attempting to download $ename to $efname." >> "${efname%/*}/export.log"
            # Download the export package to the supplied directory with the name we generated.
            $admincli $insecopt --output json -p "$srcprofile" transfer download --id "$expid" --file "$efname"
            RC=$?

            if [ "$RC" = "0" ]
                then
                echo "NOTE: Download completed successfully."
                echo "$(date +"%F %T %Z") NOTE: Download of export $ename to $efname succeeded."  >> "${efname%/*}/export.log"

                # Delete the export from the source environment once it has been downloaded.
                echo "NOTE: Deleting the export package from the source."
                echo "y" | $admincli $insecopt --output json -p "$srcprofile" transfer delete --id "$expid"; echo ""
                else
                echo "ERROR: Download attempt failed with return code $RC"
                echo "$(date +"%F %T %Z") ERROR: Download of export $ename - $expid failed." >> "${efname%/*}/export.log"
                downfail=1
                fail=1
            fi
            else
            echo "ERROR: Export was not successful."
            echo "NOTE: Moving output to ${efname%/*}/$ename.err for later review"
            mv "$tmpfile" "${efname%/*}/$ename.err"
            echo "$(date +"%F %T %Z") ERROR: Export $ename failed. Output moved to ${efname%/*}/$ename.err" >> "${efname%/*}/export.log"
            exportfail=1
            fail=1
        fi
    fi
}

# Define a function to create an export and download it for endpoint exports.
# This process needs $srcprofile, $admincli, $ename, $expid, $efname, $uri already set.
# If the function is successful, the file $efname will exist.
# If the function fails because the export failed the output of the export command will be in the export directory.
function endpointexportdownload {
    echo "NOTE: Attempting to create export package for chunk $enum of endpoint $endpoint."
    echo "$(date +"%F %T %Z") NOTE: Attempting to create export package for chunk $enum of endpoint $endpoint." >> "${efname%/*}/export.log"
    exportfail=0
    downfail=0
    # Create a temporary file to store output from the export command
    tmpfile=$(mktemp)

    # Build an export

    # Export the package and capture the output to a file.
    $admincli $insecopt --output json -p "$srcprofile" transfer export "${incdepopt}" --request @"$package" > "$tmpfile"  2>&1
    RC=$?

    # Check if the output is blank, suggesting we encountered an issue connecting to the service. If so, wait a minute a try again (-s means if file exists and has a size greater than 0)
    if [ ! -s "$tmpfile" ]
        then 
        echo "WARN: It looks like we are having trouble connecting to the transfer service. Pausing for 60 seconds and retrying."
        echo "$(date +"%F %T %Z") WARN: It looks like we are having trouble connecting to the transfer service. Pausing for 60 seconds and retrying." >> "${efname%/*}/export.log"
        sleep 60
        echo "NOTE: Attempting (again) to create export package for chunk $enum of endpoint $endpoint."
        echo "$(date +"%F %T %Z") NOTE: Attempting (again) to create export package for chunk $enum of endpoint $endpoint." >> "${efname%/*}/export.log"
        $admincli $insecopt --output json -p "$srcprofile" transfer export "${incdepopt}" --request @"$package "> "$tmpfile"  2>&1
        RC=$?        
    fi

    # See if the export output reports the wait exceeded.
    timeout=$(grep -c "The wait time has been exceeded" "$tmpfile")
    if [ "$timeout" = "1" ]
    then
        echo "WARN: Export of package $ename has exceeded the timeout period. The script will continue."
        echo "$(date +"%F %T %Z") WARN: Export of package $ename - $endpoint chunk $enum has exceeded the timeout period. The package will need to be downloaded manually." >> "${efname%/*}/export.log"
        echo "$(date +"%F %T %Z") NOTE: Run sas-admin -p $srcprofile transfer list --name $ename to get the package ID so you can download it." >> "${efname%/*}/export.log"
        warn=1
        exportfail=1
        echo "NOTE: You will need to manually download/check this package after it completes."
        echo "NOTE: Run sas-admin -p $srcprofile transfer list --name $ename to get the package ID so you can download it."
    else
        # Check the output to see it has completed.
        complete=$(grep -c completed "$tmpfile")
        
        if [ "$RC" = "0" ] && [ "$complete" -ge 1 ]
            then
            # If completed, get the transfer ID returned.
            expid=$(grep -E -o '[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}' "$tmpfile")
            echo "NOTE: Export package $expid created successfully."
            rm "$tmpfile"
            echo "$(date +"%F %T %Z") NOTE: Export $ename created as $expid." >> "${efname%/*}/export.log"
            echo "NOTE: Downloading to $efname."
            echo "$(date +"%F %T %Z") NOTE: Attempting to download $ename to $efname." >> "${efname%/*}/export.log"
            # Download the export package to the supplied directory with the name we generated.
            $admincli $insecopt -output json -p "$srcprofile" transfer download --id "$expid" --file "$efname"
            RC=$?

            if [ "$RC" = "0" ]
                then
                echo "NOTE: Download completed successfully."
                echo "$(date +"%F %T %Z") NOTE: Download of export $ename to $efname succeeded."  >> "${efname%/*}/export.log"

                # Delete the export from the source environment once it has been downloaded.
                echo "NOTE: Deleting the export package from the source."
                echo "y" | $admincli $insecopt --output json -p "$srcprofile" transfer delete --id "$expid"; echo ""
                else
                echo "ERROR: Download attempt failed with return code $RC"
                echo "$(date +"%F %T %Z") ERROR: Download of export $ename - $expid failed." >> "${efname%/*}/export.log"
                downfail=1
                fail=1
            fi
            else
            echo "ERROR: Export was not successful."
            echo "NOTE: Moving output to ${efname%/*}/$ename.err for later review"
            mv "$tmpfile" "${efname%/*}/$ename.err"
            echo "$(date +"%F %T %Z") ERROR: Export $ename failed. Output moved to ${efname%/*}/$ename.err" >> "${efname%/*}/export.log"
            exportfail=1
            fail=1
        fi
    fi
}

# Define a function "importfrompath" that builds $efname from a supplied path $imppath for upload and import function.
# This will attempt against every .json file in the provided path.
function importfrompath {

# Confirm tgtprofile is set.
var=tgtprofile; varcheck
var=imppath; varcheck

# Confirm the target profile is valid.
profile=$tgtprofile; profilecheck

# Fail if import path is not a directory.
if [ ! -d "$imppath" ]
    then
    echo "ERROR: Import path $imppath does not appear to be a directory."
    exit 2
fi

# Get a list of files to import from the directory.
IFS=$'\n'
mapfile -t imparray < <(ls "$imppath"/*.json)

echo "NOTE: Found ${#imparray[@]} JSON files in $imppath."
echo "$(date +"%F %T %Z") NOTE: Found ${#imparray[@]} JSON files in $imppath." >> "$imppath/import.log"

for file in "${imparray[@]}"
    do
    efname="$file"

    # Run export check on the file if export check is set, otherwise set expfail to 0 to allow the import.
    if [ "$expcheck" = "1" ]
        then
        echo "$(date +"%F %T %Z") NOTE: Running export checker on $efname." >> "$imppath/import.log"
        expfile=$efname
        expcheck
        else
        expfail=0
    fi

    # If export check was successful, upload and import the json to the target.
    if [ "$expfail" = "0" ]
        then 
        echo "$(date +"%F %T %Z") NOTE: Check successful. Starting upload and import process on $efname." >> "$imppath/import.log"
        uploadandimport
        else
        echo "$(date +"%F %T %Z") ERROR: Check failed. Skipping $efname upload and import." >> "$imppath/import.log"
        fail=1
    fi

done
}

# A function to check for and optionally correct for unreachable objects in the source.
# Needs $contentpath, $admincli, $srcprofile, folders plugin
function sourcecheck {
echo "NOTE: Running source check to check for broken memberships prior to export. (--srccheck)"

# Confirm the needed variables have been set.
var=contentpath; varcheck
var=srcprofile; varcheck

# Confirm folders plugin is available.
plugin=folders; plugincheck

# Confirm srcprofile is valid profile and we are authenticated.
profile=$srcprofile; profilecheck

#Confirm path isn't empty.
pathcheck

srccheckfail=0


if [ "$isnull" = "1" ]
    then
        echo "NOTE: Folder $contentpath is empty. Skipping check."
    else

        # Get a list of child objects in the supplied folder into an temp file.
        srcchecktmp=$(mktemp)
        $admincli $insecopt --quiet --profile "$srcprofile" --output fulljson folders list-members --path "$contentpath" --recursive | jq -r '.items[] | select (.type == "child" )' > "$srcchecktmp"

        # Check if the output is blank, suggesting we encountered an issue connecting to the service. If so, wait a minute a try again (-s means if file exists and has a size greater than 0)
        if [ ! -s "$srcchecktmp" ]
            then 
            echo "WARN: It looks like we are having trouble connecting to the folders service. Pausing for 60 seconds and retrying."
            sleep 60
            echo "NOTE: Attempting (again) to get a list of child objects in $contentpath."
            
            $admincli $insecopt --quiet --profile "$srcprofile" --output fulljson folders list-members --path "$contentpath" --recursive | jq -r '.items[] | select (.type == "child" )' > "$srcchecktmp"
            RC=$?        
        fi
        
        # Get the base URL and access token from the profile.
        token=$(jq ".[\"${profile}\"]" ~/.sas/credentials.json | jq -r '."access-token"')
        baseurl=$(jq ".[\"${profile}\"]" ~/.sas/config.json | jq -r '."sas-endpoint"')
        
        var=baseurl; varcheck
        
        mapfile -t srccheckarray < <(jq -r '.uri' "$srcchecktmp")

        echo "NOTE: Found ${#srccheckarray[@]} child objects in the source path."
        
        for uri in "${srccheckarray[@]}"
            do
                url=${baseurl}${uri}
                echo -n "$url"
                RC=$(curl -s -o /dev/null -I -w "%{http_code}" "$url" --header "Authorization: Bearer $token")
                echo " HTTP Response=$RC"
                if [ "$RC" != "200" ]
                    then
                    echo "WARN: Return code for $url was $RC."
                    warn=1
                fi
                if [ "$RC" = "404" ]
                    then
                    echo "ERROR: HTTP 404 when accessing folder member $uri."
                    query="select(.uri == \"$uri\")"
                    deluri=$(jq -r "$query" "$srcchecktmp" | jq -r '.links[] | select(.rel == "delete" ) | .href' )
                    if [ -n "$deluri" ]
                    then
                        echo "ERROR: Need to delete the member using DELETE method on ${baseurl}${deluri}"
                        srccheckfail=1
                        if [ "$delete" = "1" ]
                            then
                            echo "NOTE: Delete option (--delete) is set. Attempting to delete the problem object."
                            RC=$(curl -s -o /dev/null --request DELETE -w "%{http_code}" "${baseurl}${deluri}" --header "Authorization: Bearer $token")
                            if [ "$RC" != "204" ]
                                then
                                echo "ERROR: Failed to delete object. HTTP response $RC."
                                else
                                echo "NOTE: Object deleted."
                                srccheckfail=0
                            fi
                        fi
                    else
                        echo "ERROR: Failed to resolve delete href for member uri: $uri"
                    fi
                fi
        done
        rm "$srcchecktmp"
fi

}

### Validation Function Definitions ###

# Define a function "jqcheck" to confirm that jq is installed/run-able.
function jqcheck {
    echo "NOTE: Checking if jq is installed."

    if ! jq --version > /dev/null 2>&1
        then
        echo "ERROR: This script requires the jq package."
        exit 2
    fi
    echo "jq is installed, continuing..."
}

# Define a function "sasadmcheck" to set admincli to the default path if it isn't supplied, and confirm it is executable.
function sasadmcheck {
    insecopt=""
    if [ -z "$admincli" ]
        then admincli=/opt/sas/viya/home/bin/sas-admin
    fi

    if [ ! -x "$admincli" ]
        then
        echo "ERROR: $admincli is not a valid executable. Use --admin-cli-path to specify the path to the sas-admin binary."
        exit 2
    fi
    if [ "$insec" = "1" ]
    then
        insecopt="-k"
    fi
}

# Define a function "outputcheck" to set the output path to /tmp if it isn't defined and confirm we can write to the path.
function outputcheck {
    if [ -z "$outputpath" ]
    then outputpath=/tmp
    fi
    if [ ! -w "$outputpath" ]
    then 
        echo "ERROR: Output path $outputpath is not writeable. Correct the permissions or specify another path with --output-path."
        exit 2
    fi 
}

# Define a function "plugincheck" to check that a named plugin is installed, and throw an error if it isn't.
function plugincheck {
    RC=$($admincli plugins list | cut -f1 -d' ' | grep -c $plugin)
    
if [ "$RC" -lt "1" ]
    then
    echo "ERROR: $plugin plugin is not installed. Run $admincli plugins install --repo SAS $plugin"
    exit 2
fi
}

# Define a function "profilecheck" to check if a profile is in the admin CLI's list of profiles.
# If it is, run authcheck against it to confirm we have a valid ticket and if not, log in.
function profilecheck {
    RC=$($admincli profile list | grep -o "$profile" )
    if [ -z "$RC" ]
        then
        echo "ERROR: Profile $profile is not defined. Use $admincli -p $profile profile init to set it up, or specify a different profile."
        exit 2
    fi
    authcheck
}

# Define a function "errcheck" to check if the warn or fail variable has been updated and adjust the return code accordingly.
function errcheck {
    sysrc=0
    if [ "$warn" = "1" ]
    then sysrc=1
    fi
    if [ "$fail" = "1" ]
    then sysrc=2
    fi
    exit $sysrc
}

# Define a function "authcheck" to check if we have a valid authentication token in sasadmin for a given profile.
# If not, login.
function authcheck {
    # only log in if our access token has expired.
    expire=$(jq ".[\"${profile}\"]" ~/.sas/credentials.json | jq -r '."expiry"')

    declare -i intexpire
    intexpire=$(date -d "$expire" +%s)
    declare -i intnow
    intnow=$(date +%s)

    if [ "$intexpire" -le "$intnow" ]
        then 
        # Authenticate using the supplied profile.
        echo "Current token for sas-admin CLI on profile $profile is expired."
        $admincli $insecopt -p "$profile" auth login
        RC=$?

       if [ "$RC" != "0" ]
           then 
               echo "ERROR: Authentication failed. RC=$RC"
               exit 2
       fi
    fi
}

# Define a function "varcheck" to check if a supplied variable is defined. Needs $var to be set as the variable to check.
# If the variable is in the case list it will provide more detailed information on how to correct it.
function varcheck {
    if [ -z "${!var}" ]
        then
        usage
        case $var in
        srcprofile )    echo "ERROR: Source profile is not defined, use --src-profile to set this value."
                        exit 2
                        ;;
        tgtprofile )    echo "ERROR: Target profile is not defined, use --tgt-profile to set this value."
                        exit 2
                        ;;
        contentpath )   echo "ERROR: Content path is not defined, use --content-path to set this value."
                        exit 2
                        ;;
        expfile )       echo "ERROR: Export file is not defined, use --export-file to set this value."
                        exit 2
                        ;;
        folderid )      echo "ERROR: Folder ID is not defined, use --folder-id to set this value."
                        exit 2
                        ;;
        imppath )       echo "ERROR: Import path is not defined, use --import-path to set this value."
                        exit 2
                        ;;
        * )             echo "ERROR: $var is not defined."
                        exit 2
                        ;;

        esac

    fi

    # If the variable being checked is a path, strip the trailing slash.
    if [ "$var" = "contentpath" ] || [ "$var" = "imppath" ] || [ "$var" = "baseurl" ] || [ "$var" = "endpoint" ]
        then
        if [ "${!var: -1}" = "/" ]
            then
            declare -g $var="${!var%?}"
        fi
    fi
}

# Define a function "getshortcuts" that examines and outputs references in a given content path.
function getshortcuts {
    echo "NOTE: Running shortcut function (--shortcutcheck)..."
    # Confirm the needed variables have been set.
    var=contentpath; varcheck
    var=srcprofile; varcheck

    # Confirm folders plugin is available.
    plugin=folders; plugincheck

    # Confirm srcprofile is valid profile and we are authenticated.
    profile=$srcprofile; profilecheck

    # Confirm path is not empty.
    pathcheck

    if [ "$isnull" = "1" ]
        then
            echo "NOTE: Folder $contentpath appears to be empty. Skipping."
        else
        # Create a temporary file.
        tmpfile=$(mktemp)

        # Pull down all the members into the file.
        $admincli $insecopt --output fulljson -p "$srcprofile" folders list-members --path "$contentpath" --recursive > "$tmpfile"

        # Check if the output is blank, suggesting we encountered an issue connecting to the service. If so, wait a minute a try again (-s means if file exists and has a size greater than 0)
        if [ ! -s "$tmpfile" ]
            then 
            echo "WARN: It looks like we are having trouble connecting to the folders service. Pausing for 60 seconds and retrying."
            sleep 60
            echo "NOTE: Attempting (again) to get a list of objects in $contentpath."
            
            $admincli $insecopt --output fulljson -p "$srcprofile" folders list-members --path "$contentpath" --recursive > "$tmpfile"
            RC=$?        
        fi

        # Get each defined reference type into an array.
        mapfile -t refarray < <(jq -r '.items[] | select (.type == "reference") | .contentType' "$tmpfile" | sort | uniq )
        echo "NOTE: Found ${#refarray[@]} reference objects in the source path."
        echo ""
        echo "NOTE: Shortcuts found in folder $contentpath:"
        for type in "${refarray[@]}"
            do
            # Get a count of that type
            count=$(jq -r '.items[] | select (.type == "reference") | .contentType' "$tmpfile" | grep -c "$type")
            echo "NOTE: Found $count references of contentType $type defined:"
            # List the entries
            query=".items[] | select (.type == \"reference\") | select (.contentType == \"$type\" ) |  (.name + \" \" + .uri)" 
            jq -r "$query" "$tmpfile"
            echo ""
        done

        rm "$tmpfile"
    fi
}

# Define a function "pathcheck" that will see if a supplied content path is empty.
function pathcheck {
    
    tmpfile=$(mktemp)
    if [ -z "$folderid" ]
        then
        $admincli $insecopt --output fulljson -p "$profile" folders list-members --path "$contentpath" > "$tmpfile"

        # Check if the output is blank, suggesting we encountered an issue connecting to the service. If so, wait a minute a try again (-s means if file exists and has a size greater than 0)
        if [ ! -s "$tmpfile" ]
            then 
            echo "WARN: It looks like we are having trouble connecting to the folders service. Pausing for 60 seconds and retrying."
            sleep 60
            echo "NOTE: Attempting (again) to get a list of objects in $contentpath."
            
            $admincli $insecopt --output fulljson -p "$profile" folders list-members --path "$contentpath" > "$tmpfile"
            RC=$?        
        fi
        else
        $admincli $insecopt --output fulljson -p "$profile" folders list-members --id "$folderid" > "$tmpfile"
        # Check if the output is blank, suggesting we encountered an issue connecting to the service. If so, wait a minute a try again (-s means if file exists and has a size greater than 0)
        if [ ! -s "$tmpfile" ]
            then 
            echo "WARN: It looks like we are having trouble connecting to the folders service. Pausing for 60 seconds and retrying."
            sleep 60
            echo "NOTE: Attempting (again) to get a list of objects in $contentpath."
            
            $admincli $insecopt --output fulljson -p "$profile" folders list-members --id "$folderid" > "$tmpfile"
            RC=$?        
        fi
    fi
    isnull=$(jq -r '.items' "$tmpfile" | grep -c null)
    
    rm "$tmpfile"
}

### End of Function Definitions ###

# Check that jq is installed before doing anything.
jqcheck

# If specifying --endpoint with validation options it doesn't support, throw an error
if [ -n "$endpoint" ] &&  { [ -n "$impcheck" ] || [ -n "$srccheck" ] || [ -n "$shortcutcheck" ]; }
    then
    echo "ERROR: The endpoint function does not support import check, source check or shortcut check functions."
    exit 2
fi

# If specifying endpoint and content-path, throw an error
if [ -n "$endpoint" ] && [ -n "$contentpath" ]
    then
    echo "ERROR: --endpoint and --content-path cannot both be set."
    exit 2
fi

# Execute the appropriate function based on options specified.

# If only expcheck is set, run its function directly.
if [ "$expcheck" = "1" ] && [ -z "$import" ] && [ -z "$export" ] && [ -z "$impcheck" ] # --expcheck only
    then
    sasadmcheck
    expcheck

# If only impcheck is set, run its function directly.
elif [ -z "$expcheck" ] && [ -z "$import" ] && [ -z "$export" ] && [ "$impcheck" = "1" ] # --impcheck only
    then
    sasadmcheck
    impcheck

# If export is set then run it. That function has code to handle the presence of the checking and import options.

elif [ "$export" = "1" ]
    then 
    sasadmcheck
    export

# If import is set and export isn't, we need to import from a supplied path using the importfrompath function.
elif [ "$import" = "1" ] && [ -n "$imppath" ] && [ -z "$export" ]
    then 
    sasadmcheck
    importfrompath

# If only srccheck is set, run its function directly.
elif [ "$srccheck" = "1" ] && [ -z "$import" ] && [ -z "$export" ] && [ -z "$impcheck" ] # --srccheck only
    then
    sasadmcheck
    sourcecheck

# If only shortcutcheck is set, run its function directly.
elif [ "$shortcutcheck" = "1" ] && [ -z "$import" ] && [ -z "$export" ] && [ -z "$impcheck" ] && [ -z "$expcheck" ]
    then
    sasadmcheck
    getshortcuts

# If any other combination is defined indicate as such to stdout.
else 
    echo " It looks like you have submitted an unexpected set of options. Valid combinations are"
    echo "  --impcheck"
    echo "  --expcheck"
    echo "  --srccheck"
    echo "  --shortcutcheck"
    echo "  --export [ [--import] [--impcheck] ] [--expcheck] [--srccheck] [--shortcutcheck]"
    echo "  --import --import-path [--expcheck]"
    echo ""
    usage   
    exit 2 
fi

# Capture failures into return code.
errcheck