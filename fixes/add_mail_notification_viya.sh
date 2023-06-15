#!/bin/bash

# This script will add a mail notification to a specified subscription.
# Date: 27JUL2020

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################
## Begin Edit ##
################

# Specify connection information
BASEURL=http://viya.demo.sas.com
# Define the subscription you would like to update.
SUBNAME="Backup service errors"

##############
## End Edit ##
##############

# Check if jq is installed.

echo "NOTE: Checking if jq is installed."

if ! jq --version > /dev/null 2>&1
    then
    echo "ERROR: This script requires the jq package."
    exit 2
fi

echo "NOTE: Going to try to set the communication channels for subscription \"$SUBNAME\""
echo "to both store and mail for environment at $BASEURL"

read -r -p "Enter User ID: " USERID
read -r -s -p "Enter Password: " PASS
echo ""

# Make SUBNAME URL encoded

SUBNAME=$(echo %27"$SUBNAME"%27 | sed 's/ /%20/g')
echo "URL Encoded subscription name to $SUBNAME"

# Get an authentication token.

echo "NOTE: Getting authorization token for user $USERID."

TOKEN=$(curl -s --location --request POST "$BASEURL/SASLogon/oauth/token" \
--header 'Accept: application/json' \
--header 'Content-Type: application/x-www-form-urlencoded' \
--header 'Authorization: Basic c2FzLmVjOg==' \
--data-urlencode "grant_type=password" \
--data-urlencode "username=$USERID" \
--data-urlencode "password=$PASS" | jq -r '.access_token')

if [ "$TOKEN" = "null" ]
    then
    echo "ERROR: Authorization appears to have failed. TOKEN not set."
    exit 2
fi

# Query the notification microservice for the subscription.

echo "NOTE: Searching for subscription, outputting to /tmp/subinfo."

curl -s --location --request GET "$BASEURL/notifications/subscriptions?filter=eq(name,$SUBNAME)" \
--header 'Accept: application/json' \
--header 'Content-Type: application/x-www-form-urlencoded' \
--header "Authorization: Bearer $TOKEN" > /tmp/subinfo

# Check if more than one result was provided.
COUNT=$(jq '.count' /tmp/subinfo)

if [ "$COUNT" != "1" ]
    then
    echo "ERROR: Query filter did not return exactly one result"
    exit 2
fi

echo "NOTE: Building a patch file into /tmp/patch.json"

# Build a patch file with the channels store and mail.
jq -c '.items[] | { name: .name, notificationType: .notificationType, notificationCategory: .notificationCategory,channels:["store","mail"] ,subscriberId: .subscriberId, subscriberType: .subscriberType }' /tmp/subinfo > /tmp/patch.json
echo "NOTE: Patch built."

echo "NOTE: Extracting ID."

# Get the subscription ID

ID=$(jq -r '.items[].id' /tmp/subinfo)
echo "NOTE: Subscription ID: $ID"

# Set some future date to use to filter on.
FUTUREDATE=$(date -d "next monday" +"%a, %d %b %Y %H:%M:%S %Z")

 echo ""
 echo "NOTE: Here are the current channels for the subscription."
 curl -s --location --request GET "$BASEURL/notifications/subscriptions/$ID" \
 --header 'Accept: application/json' --header 'Content-Type: application/json' \
 --header "Authorization: Bearer $TOKEN" | jq '.channels[]'

echo "NOTE: Attempting patch."

# Perform the patch.
RC=$(curl -o /dev/null -s --location -w "%{http_code}" --request PATCH "$BASEURL/notifications/subscriptions/$ID" \
 --header 'Accept: application/json' --header 'Content-Type: application/json' \
 --header "Authorization: Bearer $TOKEN" --header "If-Unmodified-Since: $FUTUREDATE" --data-binary "@/tmp/patch.json")

if [ "$RC" != "200" ]
    then
    echo "ERROR: PATCH did not succeed. Return code: $RC"
    exit 2
fi

 # Check to see if mail is now a channel.
 echo ""
 echo "NOTE: Here are the current channels for the subscription."
 curl -s --location --request GET "$BASEURL/notifications/subscriptions/$ID" \
 --header 'Accept: application/json' --header 'Content-Type: application/json' \
 --header "Authorization: Bearer $TOKEN" | jq '.channels[]'