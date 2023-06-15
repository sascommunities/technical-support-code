#!/bin/bash
#
# As the GRIDWAIT option for SASGSUB does not alter its return code based on the return code of its job
# this wrapper script will use GRIDWAIT to wait for completion and then use GRIDGETSTATUS to capture 
# the return code as its own.
# Date: 15DEC2020
#
# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

### Begin user edit ###
# Supply the LEVELDIR so the script can find the sasgsub script executable
LEVELDIR=/opt/sas/config/Lev1

### End user edit ###

# Define a usage function
function usage {
    echo ""
    echo "Usage: $0 <program.sas> [OPTIONS]"
    echo "Script uses sasgsub with GRIDSUBMITPGM and GRIDWAIT to submit a SAS program as a grid job."
    echo "When the job completes, it uses GRIDGETSTATUS to get the return code of the job, and sets "
    echo "that as its own return code."
    echo ""
}

# Check to see if we have been given any arguments.
if [ "$1" = "" ]
    then 
    usage
    exit 1
fi

# Check to see if we've been provided a path to a SAS program as our first argument, and that it is readable.

if [ ! -r "$1" ]
then
    echo >&2 "ERROR: $1 is not a readable file."
    usage
    exit 1
fi

# Define the path to the SASGSUB executable based on the supplied LEVELDIR

GSUBEXE=$LEVELDIR/Applications/SASGridManagerClientUtility/9.4/sasgsub

# Check to see if that file is executable.

if [ ! -x "$GSUBEXE" ]
then
echo >&2 "ERROR: $GSUBEXE is not a valid executable."
echo "Edit $0 and provide the correct LEVELDIR for this environment and ensure the SAS Grid Manager Client Utility has been configured."
exit 2
fi

# Confirm grep cut and awk are present
for cmd in grep cut awk
do
command -v $cmd >/dev/null 2>&1 || { echo >&2 "ERROR: This script requires $cmd, but it's not installed."; exit 1; }
done

# Pull the program path into a variable and shift to exclude it from any additional submission options.
PGM=$1
shift

# Submit the job using GRIDWAIT and pull the job ID into a variable
JOBID=$($GSUBEXE -GRIDSUBMITPGM "$PGM" "$@" -GRIDWAIT | grep Job.ID | awk '{ print $3 }' )

# Get the resulting exit code
RC=$($GSUBEXE -GRIDGETSTATUS "$JOBID" "$@" | grep "$JOBID" | grep -E -o 'RC:[0-9]+' | cut -f2 -d':')

# Exit with that code
exit "$RC"