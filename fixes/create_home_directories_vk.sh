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
    echo "  --baseurl, -b       The URL for the Viya environment."
    echo "  --setown            If a directory already exists, set its ownership to the value from Viya instead of skipping."
    echo "  --reset-identifier  This option will, for each user, delete the existing identifier."
    echo "  --useracct, -a      Allows specification of a single user ID instead of building an array from the identities service."
    echo "  --user, -u          Provide authentication user as an option in CLI instead of being prompted."
    echo "  --password, -p      Provide authentication password as an option in CLI instead of being prompted."
    echo "  --authcode, -c      Login to Viya using an authentication code rather than user and password (SSO)."
    echo "  --token, -t         Provide authentication oauth token as an option in CLI instead of logging in to SASLogon to obtain one."
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
    -b | --baseurl )            shift
                                baseurl=$1
                                ;;
    -c | --authcode )           authcode=1
                                ;;
    -h | --help )               usage
                                exit
                                ;;
    --setown )                  setown=1
                                ;;
    --reset-identifier )        reset=1
                                ;;
    -a | --useracct )           shift
                                useracct=$1
                                ;;
    -u | --user )               shift
                                user=$1
                                ;;
    -p | --password )           shift
                                pass=$1
                                ;;
    -t | --token )              shift
                                token=$1
                                ;;
    * )                         usage
                                exit 1
    esac
    shift
done

jqcheck

# Confirm we have the values we need
if [ -z "$baseurl" ] || { [ -z "$directory" ] && [ -z "$reset" ] ;}
    then
    echo "ERROR: --url and either --directory or --reset-identifier must be specified."
    exit 1
fi

if [ -n "$setown" ] && [ -z "$directory" ]
then
    echo "ERROR: --setown requires --directory is set."
    exit 1
fi

# Remove any trailing slashes
baseurl=${baseurl%/}
if [ -n "$directory" ]
    then
    directory=${directory%/}
    # Confirm the directory is a directory and we have permission to write to it.
    if [ ! -d "$directory" ] || [ ! -w "$directory" ]
        then
        echo "ERROR: $directory is not a writeable directory."
    fi
fi
# Login to Viya
echo "NOTE: Attempting to log in to $baseurl"
headers=$(mktemp)

# If using authentication code, provide the url to get the code and prompt for that code to get a token
# otherwise, prompt for user/password.
if [ -n "$token" ]
    then
    echo "NOTE: Token provided in CLI execution. Skipping login."
elif [ -n "$authcode" ]
    then
    echo "Login to SAS with this URL, and enter the authentication code provided."
    echo "$baseurl/SASLogon/oauth/authorize?client_id=sas.cli&response_type=code"
    read -r -p "Enter authentication code: " code
    token=$(curl -k -s -L -X POST "$baseurl/SASLogon/oauth/token" -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmNsaTo=' -d "grant_type=authorization_code&code=$code" -D "$headers" | sed "s/{.*\"access_token\":\"\([^\"]*\).*}/\1/g")
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
else
    if [ -z "$user" ]
        then
        read -r -p "Enter username: " user
    fi
    if [ -z "$pass" ]
        then
        read -r -s -p "Enter password: " pass && echo
    fi
    token=$(curl -k -s -L -X POST "$baseurl/SASLogon/oauth/token" -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded' -H 'Authorization: Basic c2FzLmNsaTo=' -d 'grant_type=password' -d "username=$user" -d "password=$pass" -D "$headers" | sed "s/{.*\"access_token\":\"\([^\"]*\).*}/\1/g")
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
fi

userresp=$(mktemp)
if [ -z "$useracct" ]
then
# Pull the initial list of users
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

else
echo "NOTE: --useracct was set to $useracct. Defining this as our only user."
users=("$useracct")
fi

# For each user, check to see if a directory already exists with their name in the directory supplied. If not, pull the uid/gid and create the directory.
for user in "${users[@]}"
    do
    # If the --reset-identifier option is set, call /identities/users/user_ID/identifier with the DELETE HTTP method for each user to remove any existing ID.
    if [ "$reset" = "1" ]
        then
        echo "NOTE: Deleting existing identifier for $user."
        response=$(curl -k -s -L -X DELETE "$baseurl/identities/users/${user}/identifier" -H "Authorization: Bearer $token" -o /dev/null -w "%{http_code}")
        if [ "$response" = "204" ]
        then
            echo "NOTE: Delete successful."
        elif [ "$response" = "404" ]
        then
            echo "NOTE: Identifier was not present, so no delete occurred."
        else
            echo "ERROR: HTTP Response Code: $response. Are we logged on as a SAS Administrator? Is our token expired?"
            break
        fi
    fi

    if [ -n "$directory" ]
    then
        # If the directory for a given user doesn't exist OR if the --setown option is set meaning we need to reset every user's directory ownership.
        if [ ! -d "${directory}/${user}" ] || [ "$setown" = "1" ]
            then
            # Get the identifiers for the user.
            curl -k -s -L "$baseurl/identities/users/${user}/identifier" -H "Authorization: Bearer $token" -H "Accept: application/json" > "$userresp"
            uid=$(jq -r '.uid' "$userresp")
            gid=$(jq -r '.gid' "$userresp")

            # Stop 
            if [ "$uid" = "null" ] || [ "$gid" = "null" ]
            then
                echo "ERROR: Failed to pull UID/GID values for $user. Skipping to next user."
                continue
            fi

            # If the directory doesn't exist, create it.
            if [ ! -d "${directory}/${user}" ]
                then
                
                if install -d -m 0700 -o "$uid" -g "$gid" "${directory}/${user}"
                then
                echo "NOTE: Created directory ${directory}/${user} with ownership ${uid}:${gid}"
                else
                echo "ERROR: Install command did not return code 0. Are we running as root? Exiting."
                exit 1
                fi
            
            # If the directory DOES exist and --setown option is set, then set the ownership with chown command.
            elif [ -d "${directory}/${user}" ] && [ "$setown" = "1" ]
                then
                # Check if the ownership change needs to happen.
                if [ "$(stat --format="%u" "${directory}/${user}")" != "${uid}" ] || [ "$(stat --format="%g" "${directory}/${user}")" != "${gid}" ]
                    then
                    echo "NOTE: Setting ownership of ${directory}/${user} to ${uid}:${gid}"
                    if chown "${uid}:${gid}" "${directory}/${user}"
                        then
                        echo "NOTE: Ownership set successfully."
                        else
                        echo "ERROR: Failed to set permission on directory using chown. Are we running as root? Exiting."
                        exit 1
                    fi
                    else
                    echo "NOTE: Ownership of ${directory}/${user} is already ${uid}:${gid}, Skipping."
                fi
            fi

        # If the directory exists and --setown is not set, skip any action.
        else
            echo "NOTE: Directory ${directory}/${user} appears to already exist. Skipping."
        fi
    fi
done

# Remove temp files
rm "$headers"
rm "$userresp"