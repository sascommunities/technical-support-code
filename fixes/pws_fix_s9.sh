#!/bin/bash
# This script fixes some common issues we see with the Platform Web Services web application.
# Date: 06MAR2023
#
## LSF Checks
# 1. Confirm profile.lsf is sourced (LSF_ENVDIR is set)
# 2. Confirm middle tier host is a grid client
# 3. Confirm sas installation account is an LSF administrator

## SAS Checks
# 4. Confirm LD_LIBRARY_PATH includes common and versioned paths, and ends with $LD_LIBRARY_PATH in setenv.sh
# 5. Confirm GUI_LOGDIR is set in setenv.sh
# 6. Confirm profile.lsf is present in setenv.sh
# 7. Confirm platformpws directory is not in Staging/exploded, and no duplicate jar versions are present.
# 8. Confirm SASGridManager logconfig .orig suffix is removed
# 9. Confirm we are not missing the links that setenv.sh removes/recreates on startup.

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function usage {
    echo ""
    echo "Usage: pwsfix.sh [OPTIONS]..."
    echo "Script checks for common issues with platform web services configuration that"
    echo "prevent it from starting or querying LSF successfully."
    echo ""
    echo "Options:"
    echo "  --fix                               This option will try to correct some of the issues found."
    echo "  -c, --configdir <path>              Provide a path to the SAS Configuration directory."
    echo "                                      ex. /opt/sas/config/Lev1"
    echo "  -h, --help                          Show this usage information."
    echo ""
}

# If no arguments are supplied, return the help page and terminate with a non-zero return code.
if [ "$1" = "" ]
    then
    >&2 echo "ERROR: No options supplied."
    usage
    exit 1
fi

# Read in the arguments provided and store them to environment variables.
while [ "$1" != "" ]
    do
    case $1 in
    --fix )             fix=1
                        ;;
    --configdir | -c )  shift
                        configdir=$1
                        ;;
    -h | --help )       usage
                        exit
                        ;;
    * )                 >&2 echo "ERROR: Option $1 invalid."
                        usage
                        exit 1
    esac
    shift
done

# Strip the trailing slash from configdir if it is present.
configdir=${configdir%*/}

# Fail of configdir isn't a directory
if [ ! -d "$configdir" ]
then
    echo "ERROR: $configdir is not a directory."
    usage
    exit 1
fi

# Fail of configdir doesn't contain a readable sas.servers.mid
if [ ! -r "$configdir/sas.servers.mid" ]
then
    echo "ERROR: $configdir does not appear to be a valid middle tier configuration directory (I can't read $configdir/sas.servers.mid)"
    echo "       or we are not executing as the SAS installation account."
    usage
    exit 1
fi

# Confirm commands we use are present
for cmd in grep cut awk sed tac tr head whoami date ln
do
command -v $cmd >/dev/null 2>&1 || { echo >&2 "ERROR: This script requires $cmd, but it's not installed."; exit 1; }
done

##
## LSF Checks Start
##

echo "NOTE: Checking if profile.lsf is sourced..."

# Fail if LSF_ENVDIR is not defined (profile.lsf not sourced)
if [ ! -d "$LSF_ENVDIR" ]
    then
    echo "ERROR: LSF_ENVDIR is not set to a directory. Has profile.lsf been sourced?"
    echo "       Try running . LS_TOP/conf/profile.lsf where LS_TOP is your LSF installation directory."
    echo "       Then run the script again."
    exit 1
    else
    echo "NOTE: LSF_ENVDIR is set: $LSF_ENVDIR"
    echo
fi

# Set the environment variable "clusterfile" to the cluster file for LSF
clusterfile=$(find "$LSF_ENVDIR" -maxdepth 1 -regex '.*/lsf.cluster.[^.]+')

echo "NOTE: Checking if we are an LSF client..."

# Run lsid to confirm we are a valid LSF client and pull the LSF version

lsfver="$(lsid | head -1 | cut -f5 -d' ' | tr -d ',')"

if [ -z "$lsfver" ]
    then
    echo "ERROR: Unable to get LSF version."
    echo "       Is this host configured as a grid client?"
    echo "       Are the LSF services running on the grid hosts?"
    # This outputs the hosts section of the cluster file
    echo "Host section of cluster file $clusterfile:"
    sed -rn '/Begin.+Host/, /End.+Host/p' "$clusterfile" | grep -Ev "(^[[:space:]]*#.*|^[[:space:]]*$)"
    echo "Floating clients lines from $clusterfile:"
    grep -Ev "(^[[:space:]]*#.*|^[[:space:]]*$)" "$clusterfile" | grep -i float
    exit 1
    else
    echo "NOTE: LSF version returned: $lsfver"
    echo
fi

echo "NOTE: Checking if we are an LSF administrator..."

# Since we are supposed to be running as the sas installation account, check to see that we are an LSF administrator
if [ "$(sed -rn '/Begin.+ClusterAdmins/, /End.+ClusterAdmins/p' "$clusterfile" | grep "$(whoami)" | cut -f1 -d' ' | tr '[:upper:]' '[:lower:]')" != "administrators" ]
    then
        echo "ERROR: It doesn't look like we are an LSF administrator."
        echo "We are running as user: $(whoami)"
        echo "ClusterAdmins section of $clusterfile:"
        sed -rn '/Begin.+ClusterAdmins/, /End.+ClusterAdmins/p' "$clusterfile"
        exit 1
    else
        echo "We are running as user: $(whoami)"
        echo "ClusterAdmins section of $clusterfile:"
        sed -rn '/Begin.+ClusterAdmins/, /End.+ClusterAdmins/p' "$clusterfile"
        echo
fi

##
## SAS Checks Start
##

## Confirm LD_LIBRARY_PATH defined in setenv.sh includes both common and versioned path, and that the reference
## to the existing LD_LIBRARY_PATH value is at the end of the declaration.

setenv="$configdir/Web/WebAppServer/SASServer14_1/bin/setenv.sh"

echo "NOTE: Checking LD_LIBRARY_PATH setting in setenv.sh for SAS Server 14..."

if [ ! -r "$setenv" ]
    then
    echo "ERROR: We do not have read permission on $setenv"
    echo "       Are we running as the SAS installation account?"
    exit 1
fi

# This command finds the last instance of LD_LIBRARY_PATH defined in the setenv.sh file (tac is cat backwards, so we are searching bottom up).

ldlp=$(tac "$setenv" | grep -m1 -E '^[[:space:]]*LD_LIBRARY_PATH=' | cut -f2 -d'=' | tr -d '"')

# Define a function that corrects the LD_LIBRARY_PATH value in setenv.sh
function newsetenv {

    # Grab the architecture from the existing ldlp variable:
    arch="$(echo "$ldlp" | grep -Eo 'common.[^\/]+' | cut -f2 -d'/')"

    # If the LSF major version we pulled was 10, use the lsf10.1 versioned library path, otherwise use the other one (lsf8.0.1)
    if [ "${lsfver%%.*}" = "10" ]
        then
        newldlp="\$GUI_LIBDIR/common/${arch}/:\$GUI_LIBDIR/lsf10.1/${arch}/:\$LD_LIBRARY_PATH"
        else
        newldlp="\$GUI_LIBDIR/common/${arch}/:\$GUI_LIBDIR/lsf8.0.1/${arch}/:\$LD_LIBRARY_PATH"
    fi

    # If fix is set, try to comment out the existing line and add the new one.
    if [ "$fix" = "1" ]
    then
        echo "NOTE: Setting new LD_LIBRARY_PATH..."

        # Confirm we can write to setenv.sh
        if [ -w "$setenv" ]
            then
                # Comment out the existing LD_LIBRARY_PATH setting we pulled.
                echo "NOTE: Commenting out existing LD_LIBRARY_PATH setting in $setenv..."
                sed -r -i."$(date +%d%b%Y_%H%M%S%N)" 's/^[[:space:]]*LD_LIBRARY_PATH=/#LD_LIBRARY_PATH=/g' "$setenv"

                # Add to the end of setenv.sh a new LD_LIBRARY_PATH variable definition using our built value.
                echo "NOTE: Adding new line to $setenv..."
                echo "LD_LIBRARY_PATH=\"$newldlp\"" >> "$setenv"
                echo "NOTE: Now LD_LIBRARY_PATH value is set in $setenv as:"
                tac "$setenv" | grep -m1 -E '^[[:space:]]*LD_LIBRARY_PATH='
                echo
        else
            echo "ERROR: We do not have write permission on $setenv"
            exit 1
        fi
    else
    # If fix isn't set, just write out what it should be changed to in the script output.
        echo "ACTION: Comment out the existing LD_LIBRARY_PATH and add this line to $setenv:"
        echo "        LD_LIBRARY_PATH=\"$newldlp\""
        echo
    fi
}

## Check if GUI_LIBDIR is used twice
if [ "$(echo "$ldlp" | grep -o GUI_LIBDIR | wc -l)" != "2" ]
then
    echo "WARN: LD_LIBRARY_PATH does not reference GUI_LIBDIR twice, so we may be missing a reference:"
    echo "      $ldlp"
    echo
    # If so, run the function to fix LD_LIBRARY_PATH
    newsetenv
fi

## Check if $LD_LIBRARY_PATH is at the end (if the function was already run above it will be.)
if [ "${ldlp%%:*}" = "\$LD_LIBRARY_PATH" ]
    then
    echo "WARN: LD_LIBRARY_PATH references existing contents before PWS additions."
    echo "      $ldlp"
    echo
    newsetenv
fi

# Confirm GUI_LOGDIR is set in setenv.sh (See SAS Note 68189 for more info: https://support.sas.com/kb/68/189.html)
logdir=$(tac "$setenv" | grep -m1 -E '^[[:space:]]*GUI_LOGDIR=' | cut -f2 -d'=')

if [ -z "$logdir" ]
    then
    echo "WARN: GUI_LOGDIR is not set in setenv.sh"
    if [ "$fix" = "1" ]
    then
        if [ -w "$setenv" ]
            then
                # Take a backup
                cp -p "$setenv" "${setenv}.$(date +%d%b%Y_%H%M%S%N)"
                # Add the setting for GUI_LOGDIR and export it
                echo "GUI_LOGDIR=$configdir/Web/Logs/SASServer14_1" >> "$setenv"
                echo "export GUI_LOGDIR" >> "$setenv"
            else
                echo "ERROR: We do not have read permission to edit $setenv"
                exit 1
        fi
    else
    echo "ACTION: Add these lines to $setenv:"
    echo "        GUI_LOGDIR=$configdir/Web/Logs/SASServer14_1"
    echo "        export GUI_LOGDIR"
    echo
    fi
fi

# Confirm profile.lsf is in setenv.sh
echo "NOTE: Checking that profile.lsf is sourced in setenv.sh."
profilect=$(grep -Ec "^[[:space:]]*\.[[:space:]]*$LSF_ENVDIR/profile.lsf" "$setenv")
echo "NOTE: Found $profilect instance(s) of profile.lsf being sourced."
if [ "$profilect" -eq 0 ]
then
    echo "WARN: $LSF_ENVDIR/profile.lsf is not sourced in $setenv"
    if [ "$fix" = "1" ]
    then
        echo "NOTE: Adding line to setenv.sh: . $LSF_ENVDIR/profile.lsf"
        # Take a backup
        cp -p "$setenv" "${setenv}.$(date +%d%b%Y_%H%M%S%N)"
        echo ". $LSF_ENVDIR/profile.lsf" >> "$setenv"
        echo
    else
        echo "ACTION: Add this line to setenv.sh: . $LSF_ENVDIR/profile.lsf"
        echo
    fi
fi
echo

# Confirm no duplicate versioned JARs, and platformpws directory is not in Staging.
## See SAS Note 69872 for more info. https://support.sas.com/kb/69/872.html

echo "NOTE: Checking for the presence of $configdir/Web/Staging/exploded/platformpws"

if [ -d "$configdir/Web/Staging/exploded/platformpws" ]
then
    echo "WARN: Found platformpws directory in $configdir/Web/Staging/exploded."
    if [ "$fix" = "1" ]
        then
        echo "NOTE: Removing $configdir/Web/Staging/exploded/platformpws"
        rm -rf "$configdir/Web/Staging/exploded/platformpws"
        echo
        else
        echo "ACTION: The directory $configdir/Web/Staging/exploded/platformpws should be removed."
        echo "        Run: rm -rf $configdir/Web/Staging/exploded/platformpws"
        echo
    fi
else
    echo "NOTE: $configdir/Web/Staging/exploded/platformpws not found."
    echo
fi

echo "NOTE: Checking for duplicate versioned JAR files in the deployed platform.web.services.war application."

libdir="$configdir/Web/WebAppServer/SASServer14_1/sas_webapps/platform.web.services.war/WEB-INF/lib/"

# Search for duplicate versions of JAR files (this command strips the version away and sees if we find the same prefix twice.)
duplicates=$(find "$libdir" -type f -name '*.jar' -printf '%f\n' | sed -r 's/(^[._A-Z0-9a-z\-]+)-.*/\1/' | sort | uniq -c | grep -cv 1)
echo "Found $duplicates duplicates"
echo
if [ "$duplicates" -ge 1 ]
then
    echo "WARN: Found multiple versions of the same JAR file in $libdir"
    echo "ACTION: Rebuild/redeploy PlatformWebServices web application to correct if platformpws directory is not in $configdir/Web/Staging/exploded."
    find "$libdir" -name "$(find "$libdir" -type f -name '*.jar' -printf '%f\n' | sed -r 's/(^[._A-Z0-9a-z\-]+)-.*/\1/' | sort | uniq -c | grep -v 1 | awk '{print $2}')*"
    echo
fi

# Confirm SASGridManager logconfig .orig suffix is removed (SAS Note 68188: https://support.sas.com/kb/68/188.html)
# Get the name of the file starting with "SASGridManager" in the LogConfig directory.
sgmxml=$(find "$configdir/Web/Common/LogConfig" -name "SASGridManager*")

# If it ends in "orig" instead of "xml", we need to take action.
if [ "${sgmxml##*.}" = "orig" ]
then
    echo "WARN: SASGridManager-log4j.xml file is named incorrectly."
    echo "      $sgmxml"
    if [ "$fix" = "1" ]
    then
        if [ -w "${sgmxml}" ] && [ ! -e "${sgmxml%.*}" ]
            then
            echo "NOTE: Renaming file by running: mv $sgmxml ${sgmxml%.*}"
            mv "$sgmxml" "${sgmxml%.*}"
            echo
            else
            echo "ERROR: ${sgmxml} is not writeable or ${sgmxml%.*} already exists."
            exit 1
        fi
    else
    echo "ACTION: Rename the file by running: mv $sgmxml ${sgmxml%.*}"
    echo
    fi
fi

# Confirm we are not missing the links that setenv.sh removes/recreates on startup.
base="$libdir/common"

function createlink {
    if [ -L "$base/$arc/$link" ]
        then
        echo "NOTE: Link exists: $base/$arc/$link"
        else
        echo "WARN: Link does not exist: $base/$arc/$link -> $file"
        if [ "$fix" = "1" ]
        then
            echo "NOTE: Creating link."
            ln -s "$file" "$base/$arc/$link"
        else
            echo "ACTION: Run this command to create the link: ln -s $file $base/$arc/$link"
        fi
    fi
}

# This loop checks for .so files in the linux architectures.
for arc in x86-64-sol10 sparc-sol10-64 linux-x86_64
do
    echo "NOTE: Checking $arc for presence of target files and links."
    for file in libicuuc.so.57.1 libicudata.so.57.1
    do
        if [ -f "$base/$arc/$file" ]
        then
            echo "NOTE: Target library exists: $base/$arc/$file"
            case ${file%%.*} in
              libicuuc )    link="libicuuc.so" && createlink
                            link="libicuuc.so.57" && createlink
                            ;;
              libicudata )  link="libicudata.so" && createlink
                            link="libicudata.so.57" && createlink
                            ;;
            esac
        else
            echo "ERROR: Target library missing: $base/$arc/$file"
            echo "       Rebuild and redeploy Platform Web Services web application."
            exit 1
        fi
    done
    echo
done

arc="hpuxia64"
echo "NOTE: Checking $arc for presence of target files and links."
    for file in libicuuc.sl.57.1 libicudata.sl.57.1
    do
        if [ -f "$base/$arc/$file" ]
        then
            echo "NOTE: Target library exists: $base/$arc/$file"
            case ${file%%.*} in
              libicuuc )    link="libicuuc.sl" && createlink
                            link="libicuuc.sl.57" && createlink
                            ;;
              libicudata )  link="libicudata.sl" && createlink
                            link="libicudata.sl.57" && createlink
                            ;;
            esac
        else
            echo "ERROR: Target library missing: $base/$arc/$file"
            echo "       Rebuild and redeploy Platform Web Services web application."
            exit 1
        fi
    done
echo
arc="aix5-64"
echo "NOTE: Checking $arc for presence of target files and links."
    for file in libicuuc57.1.a libicudata57.1.a
    do
        if [ -f "$base/$arc/$file" ]
        then
            echo "NOTE: Target library exists: $base/$arc/$file"
            case ${file%%.*} in
              libicuuc57 )      link="libicuuc.a" && createlink
                                link="libicuuc57.a" && createlink
                                ;;
              libicudata57 )    link="libicudata.a" && createlink
                                link="libicudata57.a" && createlink
                                ;;
            esac
        else
            echo "ERROR: Target library missing: $base/$arc/$file"
            echo "       Rebuild and redeploy Platform Web Services web application."
            exit 1
        fi
    done
    echo
    echo "NOTE: PWS Fix script completed."