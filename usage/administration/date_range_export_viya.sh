#!/bin/bash
# Script that builds a transfer package JSON based on the results of a date filtered search.
# i.e. Export objects created between date A and date B.
# Date: 13SEP2021

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0


# Check for jq
    echo "NOTE: Checking if jq is installed."
 
    if ! jq --version > /dev/null 2>&1
        then
        echo >&2 "ERROR: This script requires the jq package."
        exit 1
    fi
    echo "jq is installed, continuing..."

# Gather authentication credentials
read -r -p "Enter base URL (https://viya.example.com): " baseurl

read -r -p "Enter username: " user

read -r -s -p "Enter password: " pass && echo

read -r -p "Enter date range start (1969-01-01T00:00:00.000Z): " drstart
read -r -p "Enter date range end (1969-12-31T23:59:59.999Z): " drend

# Get an access token
token=$(curl -k -s -L -X POST "$baseurl/SASLogon/oauth/token" -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmNsaTo=' -d 'grant_type=password' -d "username=$user" -d "password=$pass" | sed "s/{.*\"access_token\":\"\([^\"]*\).*}/\1/g")

# Make a temporary file to store these objects
content=$(mktemp)

# Perform a search
curl -s -L -X POST "$baseurl/search/content?fields=resourceUri&faceted=false&limit=100" --header 'Content-Type: text/plain' --header "Authorization: Bearer $token" -d "and(matchAny(\"*\"),le(\"modifiedTimeStamp\",$drend),ge(\"modifiedTimeStamp\",$drstart))" > "$content"

# Get total qty
count=$(jq '.count' "$content")

if [ "$count" -le 0 ]
    then
        >&2 echo "ERROR: Found $count results."
        exit 1
fi

echo "NOTE: Found $count search results."

# Build an array of resource URIs
mapfile -t uris< <(jq '.items[].resourceUri' "$content")

# Check for a next link
nexturl=$(jq -r '.links[] | select(.rel == "next")|.href' "$content")

# Iterate through all next links to fully populate the array with resource uris.
while [ -n "$nexturl" ]
    do
    curl -k -s -L "${baseurl}${nexturl}" --header 'Content-Type: text/plain' --header "Authorization: Bearer $token" -d "and(matchAny(\"*\"),le(\"modifiedTimeStamp\",$drend),ge(\"modifiedTimeStamp\",$drstart))" > "$content"
    mapfile -t -O "${#uris[@]}" uris < <( jq '.items[].resourceUri' "$content")
    nexturl=$(jq -r '.links[] | select(.rel == "next") | .href' "$content")
done

# We now have a bash array with all the URIs, which we can convert to a JSON array with jq -s.

# Build the transfer file 
echo "${uris[@]}" | jq -s  --arg exportname "rangeexport-$(date -I'seconds')" '. as $uri | {"version": 1,"name":$exportname,"description": "Export built by date_range_export.sh", "items":[]}  | .items = $uri' > "$content"

# Provide file.
echo "NOTE: Export request complete."
echo "NOTE: Run sas-admin --output text transfer export --request @$content to create the export package."