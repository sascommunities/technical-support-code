#!/bin/bash
# log_level_check_v3.sh
# This script will query the SAS Configuration Server and CAS to check for loggers set to TRACE or DEBUG.
# If any are set it will send an email to the value set in the email variable below.
# The script uses curl's -n to authenticate to CAS to perform that check, so requires a user and password be
# provided in a .netrc file located in the execution user's home directory with 600 permission in the format:
# machine <cas-controller> login <user> password <password>
# It is intended to be run on the Viya server directly as it uses consul.conf, client.token, sas-bootstrap-config and vault-ca.crt in default paths.
# It expects the jq and mail commands to be installed.
# Date: 08OCT2020

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0


### Begin Edit ###

# Name of the environment to use in the subject of the email.
deployname="Demo Viya instance"

# Notification email address. Multiple addresses may be specified, comma separated.
email="notification@example.com"

# Optional cc email address
ccemail="ccnotify@example.com"

# Hostname of the CAS server to populate the cURL command.
cashost="cas.demo.sas.com"

# Optional final line of body of notification email.
message="Please contact admin@example.com with any questions."

### End Edit ###

# Check for .netrc
if [ ! -r ~/.netrc ]
    then
        echo "ERROR: File ~/.netrc is not present and readable."
        exit 2
fi

# Check .netrc permissions
if [ "$(stat -c %a ~/.netrc | sed 's/^.//')" != "00" ]
    then
        echo "ERROR: File ~/.netrc permissions are not limited to owner. Run chmod 600 ~/.netrc to correct."
        exit 2
fi

# Check .netrc contents
if [ "$(grep machine.$cashost ~/.netrc | wc -w)" != "6" ]
    then
        echo "ERROR: ~/.netrc does not contain the host $cashost or is not formatted correctly."
        echo "ERROR: Update the contents to match: machine $cashost login <userid> password <password>."
        exit 2
fi

# Confirm jq is installed
if ! jq --version > /dev/null 2>&1
    then
        echo "ERROR: This script requires the jq package."
        exit 2
fi

# Confirm mail is installed
if ! mail -V > /dev/null 2>&1
    then
        echo "ERROR: This script requires the mail command. (mailx package)"
        exit 2
fi
ctoken="/opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/client.token"
ca="/opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/vault-ca.crt"

# Confirm we have permission on files we need.
if [ ! -r /opt/sas/viya/config/consul.conf ]
    then
        echo "ERROR: No read permission on file /opt/sas/viya/config/consul.conf."
        exit 2
fi
if [ ! -r $ctoken ]
    then
        echo "ERROR: No read permission on file $ctoken."
        exit 2
fi
if [ ! -r $ca ]
    then
        echo "ERROR: No read permission on file $ca."
        exit 2
fi
if [ ! -x /opt/sas/viya/home/bin/sas-bootstrap-config ]
    then
        echo "ERROR: No execute permission on file /opt/sas/viya/home/bin/sas-bootstrap-config"
        exit 2
fi

# Confirm we can successfully authenticate to cas on the host provided.
rc=$(curl -n -s https://$cashost:8777/cas --cacert $ca -o /dev/null -w "%{http_code}")
if [ "$rc" != "200" ]
    then
        echo "ERROR: Failed to authenticate to CAS with credentials in .netrc. HTTP response code $rc."
        exit 2
fi

# Source consul.conf 
# shellcheck source=/dev/null
. /opt/sas/viya/config/consul.conf

# Export consul token
CONSUL_HTTP_TOKEN=$(sudo cat /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/client.token)
export CONSUL_HTTP_TOKEN
# Create temporary files to hold the microservice and cas reports
mstmp=$(mktemp)
cstmp=$(mktemp)

# Run sas-bootstrap-config to query the SAS Configuration Server for any logging.level objects set to TRACE or DEBUG, writing them to the temp file.
/opt/sas/viya/home/bin/sas-bootstrap-config kv read --recurse config/| grep -E 'logging.level.*(TRACE|DEBUG)' > "$mstmp"

# Run curl against the cas/loggers endpoint to get the log levels set, and filter this for Trace and Debug level with jq, writing the output to the temp file.
curl -s -n https://$cashost:8777/cas/loggers --cacert $ca | jq -r '.[] | select((.level == "Trace") or (.level == "Debug")) | ("Logger: " + .name + " " + "Level: " + .level)' > "$cstmp"

# Count how many objects were found in each.
 countms=$(wc -l < "$mstmp")
 countcs=$(wc -l < "$cstmp")

# If either report contains entries, send an email notification.
 if [[ $countms -gt 0 ]] || [[ $countcs -gt 0 ]]
    then 
        # Make a temporary file to store the body of the email.
        tmpfile=$(mktemp)
        # Write a heading for the microservice report.
        {
        echo "### Viya Microservice Loggers ###" 
        # Write the microservice report to the email body.
        cat "$mstmp" 
        echo "" 
        # Write a heading for the CAS report.
        echo "### CAS Loggers ###" 
        # Write the CAS report to the email body.
        cat "$cstmp" 
        echo "" 
        echo "### End Report ###" 
        echo "" 
        # Write a call to action asking the recipient to revert the settings if they are not needed.
        echo "If this is not currently needed, please revert these logger settings." 
        echo "$message" 
        } > "$tmpfile"
        # Send the email.
        if [ -n "$ccemail" ]
            then 
                mail -s "$deployname has $countms microservice and $countcs CAS debug loggers enabled." -c "$ccemail" $email < "$tmpfile"
            else 
                mail -s "$deployname has $countms microservice and $countcs CAS debug loggers enabled." $email < "$tmpfile"
        fi
        # Remove the temp body file.
        rm "$tmpfile"
 fi
# Remove the temp files.
rm "$mstmp" "$cstmp"