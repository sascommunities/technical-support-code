#!/bin/bash
#
# Script that pulls all users from identities/users and then pulls their uid/gid from identities/users/<user>/identifier
# then creates a home directory in the supplied path named <user> with ownership matching the uid/gid returned.
# Date: 11AUG2021

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Define a "usage" function that explains the syntax.
function usage {
    echo ""
    echo "Usage: home_dir_builder.sh [OPTIONS]..."
    echo "Script calls /identities/users to get a list of users and then for each one calls"
    echo "/identities/users/<user>/identifier to get the uid and gid. It will then create a"
    echo "path in the supplied parent directory named '<user>' with ownership of that uid/gid."
    echo ""
    echo "Options:"
    echo "  --directory, -d     The path where you would like to create the home directories."
    echo "  --url, -u           The URL for the Viya environment."
    echo "  --authcode, -c      Login to Viya using an authentication code rather than user and password (SSO)."
    echo "  --help, -h          Return this usage information page."
    echo ""
}

function jqcheck {
    echo "NOTE: Checking if jq is installed."
    if ! jq --version > /dev/null 2>&1
        then
        echo "ERROR: This script requires the jq package."
        exit 2
    fi
    echo "jq is installed, continuing..."
}

# If no arguments are supplied, return the help page and terminate with a non-zero return code.
if [ "$1" = "" ]
    then 
    usage
    exit 1
fi

# Read in the arguments provided and store them to environment variables.
while [ "$1" != "" ]
    do
    case $1 in
    -d | --directory )          shift
                                directory=$1
                                ;;
    -u | --url )                shift
                                baseurl=$1
                                ;;
    -c | --authcode )           authcode=1
                                ;;
    -h | --help )               usage
                                exit
                                ;;
    * )                         usage
                                exit 1
    esac
    shift
done

jqcheck

# Confirm we have the values we need
if [ -z "$directory" ] || [ -z "$baseurl" ]
    then
    echo "ERROR: Both --directory and --url must be specified."
    exit 1
fi

# Remove any trailing slashes
baseurl=${baseurl%/}
directory=${directory%/}

# Confirm the directory is a directory and we have permission to write to it.
if [ ! -d "$directory" ] || [ ! -w "$directory" ]
    then
    echo "ERROR: $directory is not a writeable directory."
fi

# Login to Viya
echo "NOTE: Attempting to log in to $baseurl"
headers=$(mktemp)

# If using authentication code, provide the url to get the code and prompt for that code to get a token
# otherwise, prompt for user/password.
if [ -n "$authcode" ]
    then
    echo "Login to SAS with this URL, and enter the authentication code provided."
    echo "$baseurl/SASLogon/oauth/authorize?client_id=sas.cli&response_type=code"
    read -r -p "Enter authentication code: " code
    token=$(curl -k -s -L -X POST "$baseurl/SASLogon/oauth/token" -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmNsaTo=' -d "grant_type=authorization_code&code=$code" -D "$headers" | sed "s/{.*\"access_token\":\"\([^\"]*\).*}/\1/g")
else
    read -r -p "Enter username: " user
    read -r -s -p "Enter password: " pass && echo
    token=$(curl -k -s -L -X POST "$baseurl/SASLogon/oauth/token" -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmNsaTo=' -d 'grant_type=password' -d "username=$user" -d "password=$pass" -D "$headers" | sed "s/{.*\"access_token\":\"\([^\"]*\).*}/\1/g")
fi

# Confirm token successfully acquired.
rc=$(grep -c 'HTTP.*200' "$headers")
if [ "$rc" -ne 1 ] || [ -z "$token" ]
    then
        echo "ERROR: Login unsuccessful."
        cat "$headers"
        rm "$headers"
        exit 1
fi

echo "NOTE: Successfully logged in."

# Pull the initial list of users
userresp=$(mktemp)
curl -k -s -L "$baseurl/identities/users" -H "Authorization: Bearer $token" -H "Accept: application/json" > "$userresp"
echo "NOTE: Pulling users into file $userresp."
# Create an array of users
mapfile -t users < <( jq -r '.items[].id' "$userresp" )

# Check for a next link
nexturl=$(jq -r '.links[] | select(.rel == "next") | .href' "$userresp")

# Iterate through all next links to fully populate the array with user ids.
while [ -n "$nexturl" ]
    do
    curl -k -s -L "${baseurl}${nexturl}" -H "Authorization: Bearer $token" -H "Accept: application/json" > "$userresp"
    mapfile -t -O "${#users[@]}" users < <( jq -r '.items[].id' "$userresp" )
    nexturl=$(jq -r '.links[] | select(.rel == "next") | .href' "$userresp")
done

# We now have an array, "users" that contains every user ID.
echo "NOTE: Found ${#users[@]} users defined."

# For each user, check to see if a directory already exists with their name in the directory supplied. If not, pull the uid/gid and create the directory.
for user in "${users[@]}"
    do
    if [ ! -d "${directory}/${user}" ]
        then
        curl -k -s -L "$baseurl/identities/users/${user}/identifier" -H "Authorization: Bearer $token" -H "Accept: application/json" > "$userresp"
        uid=$(jq -r '.uid' "$userresp")
        gid=$(jq -r '.gid' "$userresp")
        install -d -m 0700 -o "$uid" -g "$gid" "${directory}/${user}"
        echo "NOTE: Created directory ${directory}/${user} with ownership ${uid}:${gid}"
        else
        echo "NOTE: Directory ${directory}/${user} appears to already exist. Skipping."
    fi
done

# Remove temp files
rm "$headers"
rm "$userresp"
