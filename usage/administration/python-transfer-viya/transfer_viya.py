#!/usr/bin/env python3
# Purpose: This python script replaces the functionality of the transfer.sh bash shell script, 
# removing the reliance on the SAS Viya CLI and instead making all REST API calls directly.
# Date: 12MAY2025
#
# Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## INTRODUCTION ##
#  The main additional functionality being provided by the script is:
#  EXPORTING (--exp)
#   1. Given a path to export, export each object in that path as a separate package individually. (--content-path)
#   2. Given an endpoint to export (e.g. /reports/reports), export every such object (e.g. /reports/reports/report-id) 
#       in a supplied chunk size (e.g. 10 reports per export) (--endpoint) (--chunksize)
#  IMPORTING (--imp)
#   3. Given a supplied path of packages, import each one.
#  VALIDATION
#   4. Perform a check for broken memberships in a given content folder (folder members whose URI do not exist). (--foldercheck)
#   5. After creating an export file, check it's contents include parent folders, and match the exported folder. (--exportcheck)
#   6. After importing, confirm the source and target environments content match. (--importcheck)
#   7. Outputs reference objects in a folder (shortcuts), as these are not exported and would need to be recreated. (--shortcutcheck)
#  ADDITIONAL FUNCTIONALITY
#   8. Empty a single user or all user's recycle bins to reduce export package size when exporting user directories. (--emptyrb [--user])
#   9. Copy Logon Manager's shadow users from the source to the destination. (--usermigrate)

## USAGE ##

### Validation Functions ###

#### Import Check ####
# This set of options instructs the script to confirm child objects in a supplied path 
# in the source environment are present in the target. This confirms an import completed successfully.

# transfer_viya.py --importcheck --content-path /Users/sasdemo --src-profile Source --target-profile Target

#### Export Check ####
# This set of options instructs the script to check a supplied export package for missing parent objects.
# If a folder ID is supplied, it will also check to see if the package is missing any objects present in the folder.

# transfer_viya.py --exportcheck --export-file /tmp/Users_sasdemo_2020-08-05_150000.json [--folder-id <GUID>] --src-profile Source

#### Folder Check ####
# This set of options checks the supplied folder for any broken memberships. For example, if a file is listed as being in a 
# folder, it will check to see if the file is present. If not, it can optionally delete the invalid membership.

# transfer_viya.py --foldercheck --content-path /Users/sasdemo --src-profile Source [--delete]

#### Shortcut Check ####
# This set of options check the supplied folder for all reference-type objects, which are not included in an export.

# transfer_viya.py --shortcutcheck --content-path /Users/sasdemo --src-profile Source 

### Main Functions ###
#### Export ####
# This set of options will create and download an export package for each folder within a supplied content path.
# After downloading successfully it will remove the package it created. Adding the foldercheck option will not export packages
# if the folder has inaccessible members. Adding the exportcheck option will check the package after export. If retries is set
# and the export check fails, it will try again to download the package and check again until it gets a successful export or runs
# out of attempts.

# Content path

# transfer_viya.py --exp [--exportcheck] [--foldercheck] [--shortcutcheck] --src-profile Source --output-path /tmp --content-path /Users [--retries #]

# Endpoint

# transfer_viya.py --exp [--exportcheck] --src-profile Source --output-path /tmp --endpoint /reports/reports [--chunksize #]

#### Import ####
# This set of options will attempt to upload and import each JSON file in a supplied import path. If exportcheck is set, it will only 
# upload packages that pass the check.

# transfer_viya.py --imp --import-path "/tmp/Export_2020-08-14_082247" [--exportcheck] --tgt-profile Target

#### Export and Import ####
# This set of options is the same as the export function but after successfully downloading the package it then uploads and imports it.

# Content path

# transfer_viya.py --exp [--exportcheck] [--foldercheck] [--shortcutcheck] --imp [--importcheck] --tgt-profile Target --src-profile Source --output-path /tmp --content-path /Users [--retries #]

# Endpoint

# transfer_viya.py --exp [--exportcheck] --imp --src-profile Source --output-path /tmp --endpoint /reports/reports [--chunksize #]

#### Users ####
# This set of options will move the SASLogon user registration from the target to the source.
# This is useful when the import process needs to authenticate as a user who has not yet logged in to the target environment.

# transfer_viya.py --usermigrate --src-profile Source --tgt-profile Target

### Empty Recycle Bin ###
# This set of options will empty the recycle bin for all users or a given user in the source environment.
# This can be helpful in limiting the size of the export of a user's home directory (/Users/<username>).

# transfer_viya.py --emptyRB --src-profile Source [--user <username>]

# Import the required modules
import sys
import os
import json
import requests
import base64
import time
import argparse
from datetime import datetime,timezone, timedelta
import getpass

# This stops the --insecure option from throwing a warning.
requests.packages.urllib3.disable_warnings() 

# Test if the user has supplied any arguments and if not, instruct to run with -h/--help.
#if len(sys.argv) == 1:
#    print("No arguments supplied.")
#    print("Use --help or -h to see the available options.")

# Parse command line arguments
parser = argparse.ArgumentParser(description='transfer_viya.py: A script to transfer content between SAS Viya environments using REST APIs.')
# Main Functions:
maingroup = parser.add_argument_group('Main Functions')
maingroup.add_argument('--exp', action='store_true', help='Export content from the source environment.')
maingroup.add_argument('--imp', action='store_true', help='Import content into the target environment.')
maingroup.add_argument('--usermigrate', action='store_true', help='Migrate user registrations from source to target.')
maingroup.add_argument('--emptyRB', action='store_true', help='Empty the recycle bin for all users or a specific user.')
# Validation Functions:
validationgroup = parser.add_argument_group('Validation Functions')
validationgroup.add_argument('--exportcheck', action='store_true', help='Check exported packages for completeness.')
validationgroup.add_argument('--importcheck', action='store_true', help='Check imported content for completeness.')
validationgroup.add_argument('--foldercheck', action='store_true', help='Check for broken memberships in a folder.')
validationgroup.add_argument('--shortcutcheck', action='store_true', help='Check for reference-type objects in a folder.')
# Options:
optionsgroup = parser.add_argument_group('Shared Options')
optionsgroup.add_argument('--src-profile', help='Source environment profile name.')
optionsgroup.add_argument('--tgt-profile', help='Target environment profile name.')
optionsgroup.add_argument('--authCode', action='store_true', help='Use authorization code flow for authentication.')
optionsgroup.add_argument('--output-path', help='Path to save export files. Default is /tmp.', default='/tmp')
optionsgroup.add_argument('--content-path', help='Path of content to iterate from source or compare with importcheck.')
optionsgroup.add_argument('--import-path', help='Path to import packages from when not using both import and export functions.')
optionsgroup.add_argument('--include-dependencies', action='store_true', help='Include dependent objects when exporting content.',default=False)
optionsgroup.add_argument('--exclude-rules', action='store_true', help='Exclude rules from being exported.', default=False)
optionsgroup.add_argument('--export-file', help='Path to the export file to check when using exportcheck alone.')
optionsgroup.add_argument('--folder-id', help='Folder ID to check against the export file when using exportcheck alone.')
optionsgroup.add_argument('--endpoint', help='Endpoint to export from (e.g. /reports/reports).')
optionsgroup.add_argument('--mapping-file', help='Path to a JSON file containing substitution values for the import.')
optionsgroup.add_argument('--chunksize', type=int, default=10, help='Number of items to process in each chunk when using endpoint export (default: 10).')
optionsgroup.add_argument('--retries', type=int, default=3, help='Number of retries to export and download a package that failed exportcheck (default: 3).')
optionsgroup.add_argument('--limit', type=int, help='Limit the number of export jobs to process (for testing purposes).')
optionsgroup.add_argument('--delete', action='store_true', help='Delete broken memberships found during foldercheck.')
optionsgroup.add_argument('--timeout', type=int, default=600, help='Timeout in seconds to wait for import or export jobs to complete (default: 600).')
optionsgroup.add_argument('--wait', type=int, default=1, help='Time in seconds to wait between polling import and export job state (default: 1).')
optionsgroup.add_argument('--user', help='Specify a user to empty only their recycle bin.')
optionsgroup.add_argument('--insecure', action='store_true', help='Ignore SSL certificate validation errors.')
optionsgroup.add_argument('--verbose', action='store_true', help='Enable verbose output for debugging purposes.')

# Change the title of the built-in help section to "Help"
parser._optionals.title = "Help"
args = parser.parse_args()

# Store the insecure option in a variable. In "requests" calls we specify verify=not insecure to ignore SSL certificate validation errors.
insecure = args.insecure

# Function definitions

### Authentication Function Definitions ###

# We need to handle authentication for any given profile.
# Specifically, we need to validate that a supplied profile exists in the configuration file ~/.sas/config.json
# This file gives us the URL for the environment. Further, we need to check ~/.sas/credentials.json
# to see if we have an access token for the profile that has not expired. If no token exists we need to get one. If a token exists
# we need to check if it is expired. If it is expired we need to get a new one. If it is not expired we can use it.
# Viya supports login by way of a user ID and password, a refresh token, an authorization code, and using Kerberos.

# Lets start by defining a function to validate a given profile and return the URL for the environment.
def validate_profile(profile):
    # Check if the profile exists in the configuration file
    config_file = os.path.expanduser("~/.sas/config.json")
    if not os.path.exists(config_file):
        print(f"Configuration file {config_file} not found.")
        sys.exit(1)

    with open(config_file, "r") as f:
        config = json.load(f)

    if profile not in config:
        print(f"Profile {profile} not found in configuration file.")
        sys.exit(1)

    # Get the URL for the environment
    url = config[profile]["sas-endpoint"]
    return url

# Define a function to update the credentials file with a new access-token, refresh-token and expiry time.
def update_credentials(profile, access_token, refresh_token, expiry):
    # Check if the credentials file exists
    credentials_file = os.path.expanduser("~/.sas/credentials.json")
    if not os.path.exists(credentials_file):
        print(f"Credentials file {credentials_file} not found.")
        sys.exit(1)

    # Load the credentials file
    with open(credentials_file, "r") as f:
        credentials = json.load(f)

    # Update the credentials for the given profile
    credentials[profile] = {
        "access-token": access_token,
        "refresh-token": refresh_token,
        "expiry": expiry
    }

    # Save the updated credentials file
    with open(credentials_file, "w") as f:
        json.dump(credentials, f, indent=4)
    print(f"Credentials for profile {profile} updated successfully.")

# Define a function to decode a jwt token and output the expiration datetime in YYYY-MM-DDTHH:MM:SSZ format.
def decode_jwt(token):
    # Split the token into its parts
    parts = token.split(".")
    if len(parts) != 3:
        print("Invalid JWT token.")
        sys.exit(1)

    # Decode the payload part of the token
    payload = base64.b64decode(parts[1] + "==").decode("utf-8")
    
    # Parse the payload as JSON
    data = json.loads(payload)

    # Get the expiration time from the payload
    exp = data["exp"]

    # Convert the expiration time to a datetime object
    expiry_time = datetime.fromtimestamp(exp, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    return expiry_time

# Define a function to get a new access token, prompting for the user ID and password.
def get_access_token_pw(profile):
    # Get the URL for the environment
    url = validate_profile(profile)

    # Prompt for user ID 
    user_id = input("Enter your user ID: ")
    
    # Prompt for password, obscuring the input
    password = getpass.getpass(prompt="Enter your password: ")

    client_id = "sas.cli"
    client_secret = ""

    payload = "grant_type=password&username=%s&password=%s" % (user_id, password)

    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
        "Authorization": "Basic " + base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    }

    # Make a request to get the access token
    response = requests.post(
        f"{url}/SASLogon/oauth/token",
        data=payload,
        headers=headers,
        verify=not insecure
    )

    if response.status_code != 200:
        print(f"Failed to get access token: {response.text}")
        sys.exit(1)

    # Parse the response to get the access token, refresh token and expiry time
    data = response.json()
    access_token = data["access_token"]
    refresh_token = data["refresh_token"]
    expiry = decode_jwt(access_token)
    
    # Update the credentials file with the new access token, refresh token and expiry time
    update_credentials(profile, access_token, refresh_token, expiry)

# Define a function to get a new access token using an authorization code.
# This function should print the sas-endpoint URL + /SASLogon/oauth/authorize?client_id=sas.cli&response_type=code and then prompt for the code.
# The user should then paste the code into the prompt. The function will then use the code to get a new access token.
def get_access_token_auth_code(profile):
    # Get the URL for the environment
    url = validate_profile(profile)

    client_id = "sas.cli"
    client_secret = ""

    # Print the URL for the user to visit to get the authorization code
    print(f"Please visit the following URL to get the authorization code:")
    print(f"{url}/SASLogon/oauth/authorize?client_id={client_id}&response_type=code")

    # Prompt for the authorization code
    auth_code = input("Enter the authorization code: ")

    payload = f"grant_type=authorization_code&code={auth_code}"

    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
        "Authorization": "Basic " + base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    }

    # Make a request to get the access token
    response = requests.post(
        f"{url}/SASLogon/oauth/token",
        data=payload,
        headers=headers,
        verify=not insecure
    )

    if response.status_code != 200:
        print(f"Failed to get access token: {response.text}")
        sys.exit(1)

    # Parse the response to get the access token, refresh token and expiry time
    data = response.json()
    access_token = data["access_token"]
    refresh_token = data["refresh_token"]
    expiry = decode_jwt(access_token)
    
    # Update the credentials file with the new access token, refresh token and expiry time
    update_credentials(profile, access_token, refresh_token, expiry)

# Define a function to get a new access token using the refresh token.
def get_access_token_refresh(profile):
    # Get the URL for the environment
    url = validate_profile(profile)

    # Load the credentials file
    credentials_file = os.path.expanduser("~/.sas/credentials.json")
    with open(credentials_file, "r") as f:
        credentials = json.load(f)

    # Get the refresh token from the credentials file
    refresh_token = credentials[profile]["refresh-token"]

    client_id = "sas.cli"
    client_secret = ""

    payload = f"grant_type=refresh_token&refresh_token={refresh_token}"

    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
        "Authorization": "Basic " + base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    }

    # Make a request to get the access token
    response = requests.post(
        f"{url}/SASLogon/oauth/token",
        data=payload,
        headers=headers,
        verify=not insecure
    )

    if response.status_code != 200:
        print(f"Failed to get access token using refresh token: {response.text}")
        if args.authCode:
            get_access_token_auth_code(profile)
        else:
            get_access_token_pw(profile)

    # Parse the response to get the access token, refresh token and expiry time
    data = response.json()
    access_token = data["access_token"]
    refresh_token = data["refresh_token"]
    expiry = decode_jwt(access_token)
    
    # Update the credentials file with the new access token, refresh token and expiry time
    update_credentials(profile, access_token, refresh_token, expiry)

# Now lets define a function that will check the credentials file for a given profile to see if we have a valid access token.
# The access token is stored in the key access-token.  

# This function will use decode_jwt to check if the access token is expired or will expire within 5 minutes. If it will expire, 
# similarly use decode_jwt to check if the refresh token is expired or will expire within 5 minutes. If it is not expired, we 
# can use the refresh token to get a new access token. If the refresh token is expired we can use the get_access_token_pw function
# to log in with user ID and password or if --authCode is set, we can use the get_access_token_auth_code function to log in with an authorization code.
# These methods will update the refresh token and access token in the credentials file, so after this we can pull the access token from the credentials file
# and use it to make requests to the API.

def check_credentials(profile):
    # Check if the credentials file exists
    credentials_file = os.path.expanduser("~/.sas/credentials.json")
    if not os.path.exists(credentials_file):
        print(f"Credentials file {credentials_file} not found.")
        sys.exit(1)

    # Load the credentials file
    with open(credentials_file, "r") as f:
        credentials = json.load(f)

    # Check if the profile exists in the credentials file
    if profile not in credentials:
        print(f"Profile {profile} not found in credentials file.")
        sys.exit(1)

    # Get the access token and from the credentials file
    access_token = credentials[profile]["access-token"]
    
    # Decode the access token to get the expiry time
    expiry_time = decode_jwt(access_token)
    
    # Convert the expiry time to a datetime object
    expiry_time = datetime.strptime(expiry_time, "%Y-%m-%dT%H:%M:%S%z")

    # Get the current time in UTC
    current_time = datetime.now(timezone.utc)

    # Check if the access token is expired or will expire within 5 minutes
    if expiry_time <= current_time + timedelta(minutes=5):
        print("Access token is expired or will expire within 5 minutes.")

        # Call get_access_token_refresh, which will try to use the refresh token and if it fails will prompt for creds.
        get_access_token_refresh(profile)

# Define a function to return the access token from the credentials file, performing all the necessary validation tasks first
def get_access_token(profile):
    # Get the URL for the environment
    url = validate_profile(profile)

    # Check the credentials for the profile
    check_credentials(profile)

    # Load the credentials file
    credentials_file = os.path.expanduser("~/.sas/credentials.json")
    with open(credentials_file, "r") as f:
        credentials = json.load(f)

    # Get the access token from the credentials file
    access_token = credentials[profile]["access-token"]

    return url, access_token

### End of Authentication Function Definitions ###

### Support Function Definitions ###

#### Call REST API ####
# Borrowing from pyviyatools sharedfunctions.py call_rest_api function, though since I have two potential profiles (source and target),
# I will need to pass the profile as an argument. I also add a files option to support multipart POST requests.
def callrestapi(profile, reqval, reqtype, acceptType='application/json', contentType='application/json',data={},header={},stoponerror=1,returnEtag=False,etagIn='',noprint=0,files=None):
    
    # Use the get_access_token function to get the base URL and access token for the profile
    # This will ensure that every time we call an API, we will have a valid access token.
    baseurl, access_token = get_access_token(profile)

    # Build the headers for the request
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Accept': acceptType,
        'Content-Type': contentType
    }

    # Add in any headers passed in

    # Convert to strings
    header = {str(key):str(value) for key,value in header.items()}
    headers.update(header)
    
    # If we are passing in an etag, add it to the headers
    if etagIn:
        headers['If-Match'] = etagIn

    # Serialize the data string for the request to json format
    json_data=json.dumps(data, ensure_ascii=True)

    # Set encoding to utf-8
    json_data.encode(encoding='utf-8')

    # Convert reqtype to uppercase
    reqtype = reqtype.upper()

    # Build the full URL for the request
    url = f"{baseurl}{reqval}"

    # Make the API call
    try:
        if reqtype == 'GET':
            response = requests.get(url, headers=headers, verify=not insecure)
        elif reqtype == 'POST':
            response = requests.post(url, headers=headers, data=json_data, verify=not insecure)
        elif reqtype == 'PUT':
            response = requests.put(url, headers=headers, data=json_data, verify=not insecure)
        elif reqtype == 'DELETE':
            response = requests.delete(url, headers=headers, verify=not insecure)
        elif reqtype == 'PATCH':
            response = requests.patch(url, headers=headers, data=json_data, verify=not insecure)
        elif reqtype == 'HEAD':
            response = requests.head(url, headers=headers, verify=not insecure)
        elif reqtype == 'MPPOST':
            # For multipart POST requests, we need to use the files parameter and remove the content-type header
            # to allow requests to handle the multipart encoding.
            if 'Content-Type' in headers:
                del headers['Content-Type']
            
            # Ensure files is a dictionary with the file name and file object
            if files is None or not isinstance(files, dict):
                raise ValueError("Files must be a dictionary with file names as keys and file objects as values.")
            # Make the multipart POST request
            response = requests.post(url, headers=headers, files=files, verify=not insecure)
        else:
            raise ValueError(f"Unsupported request type: {reqtype}")
        
    except requests.exceptions.RequestException as e:
        print(f"Request failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        sys.exit(1)
        
    # If the reqtype isn't HEAD, throw an error if the status code is not 2xx
    if reqtype != 'HEAD' and not response.ok:
        if stoponerror:
            print(f"Error: {response.status_code} - {response.text}")
            response.raise_for_status()
        else:
            print(f"Warning: {response.status_code} - {response.text}")
    
    # If the reqtype is HEAD, we would want to capture a 4xx response, and the result would be the headers
    elif reqtype == 'HEAD':
        result = response.headers

    # Try to parse the response as JSON, if it fails return the text, if that fails return None
    else:
        try:
            result = response.json()
        except:
            try:
                result = response.text
            except:
                result = None
    
    # Capture the value of any etag returned in the headers
    etagOut=None
    if 'etag' in response.headers:
        etagOut=response.headers['etag']

    # ONLY if the caller specifically asked for an etag to be returned, return one
    # If using the HEAD method, return the status code as a separate result.
    if returnEtag and reqtype!="HEAD":
        return result,etagOut
    elif returnEtag and reqtype=="HEAD":
        return result,etagOut,response.status_code
    elif reqtype=="HEAD":
        return result,response.status_code
    else:
        # Otherwise, return only the result as normal.
        # This avoids breaking anything that does not expect an etag to be returned
        # in addition to the normal results.
        return result

#### Call Paged REST API ####
# This function is used to call a REST API that returns paginated results.
# It will keep calling the API until all pages are retrieved.
def call_paged_rest_api(profile, reqval, reqtype, acceptType='application/json', contentType='application/json', data={}, header={}, stoponerror=1):
    # Initialize an empty list to store all items
    all_items = []

    response = callrestapi(profile, reqval, reqtype, acceptType, contentType, data, header, stoponerror)

    # Check if the response contains items
    if 'items' in response:
        all_items.extend(response['items'])

    # Check for a rel "next" link in the response to continue pagination
    while 'links' in response and any(link.get('rel') == 'next' for link in response['links']):
        # Find the next link
        next_link = next(link['href'] for link in response['links'] if link.get('rel') == 'next')

        # Make a GET request to the next link
        response = callrestapi(profile, next_link, 'GET', acceptType, contentType, data, header, stoponerror)

        # Check if the response contains items
        if 'items' in response:
            all_items.extend(response['items'])

    return all_items

### Validate Options ###
# This function checks that the required options are supplied for each function.
def validate_options():
    
    # Check that at least one main function or validation function is selected
    if not (args.exp or args.imp or args.usermigrate or args.emptyRB or args.exportcheck or args.importcheck or args.foldercheck or args.shortcutcheck):
        parser.print_help()
        print("Error: At least one main function (--export, --import, --usermigrate, --emptyRB) or validation function (--exportcheck, --importcheck, --foldercheck, --shortcutcheck) must be selected.")
        sys.exit(1)

    # Check that source profile is supplied for functions that require it
    if (args.exp or args.usermigrate or args.emptyRB or args.exportcheck or args.importcheck or args.foldercheck or args.shortcutcheck) and not args.src_profile:
        print("Error: --src-profile is required for the selected function(s).")
        sys.exit(1)

    # Check that target profile is supplied for functions that require it
    if (args.imp or args.usermigrate or args.importcheck) and not args.tgt_profile:
        print("Error: --tgt-profile is required for the selected function(s).")
        sys.exit(1)

    # If folder-id is supplied, it must be a valid GUID format
    if args.folder_id and (not isinstance(args.folder_id, str) or len(args.folder_id) != 36):
        print("Error: --folder-id must be a valid GUID format.")
        sys.exit(1)

    # When exporting, either a content path or an endpoint must be supplied, but not both
    if args.exp and not (args.content_path or args.endpoint):
        print("Error: --content-path or --endpoint is required for export.")
        sys.exit(1)
    if args.exp and args.content_path and args.endpoint:
        print("Error: Only one of --content-path or --endpoint can be used for export.")
        sys.exit(1)

    # When using endpoint export, chunksize must be a positive integer
    if args.exp and args.endpoint and (not isinstance(args.chunksize, int) or args.chunksize <= 0):
        print("Error: --chunksize must be a positive integer when using --endpoint.")
        sys.exit(1)

    # When using exportcheck alone, an export file must be supplied
    if args.exportcheck and not args.exp and not args.export_file:
        print("Error: --export-file is required when using --exportcheck alone.")
        sys.exit(1)

    # When using import, an import path must be supplied if not using both export and import
    if args.imp and not args.exp and not args.import_path:
        print("Error: --import-path is required for import when not using both export and import.")
        sys.exit(1)

    # When using emptyRB, if a user is supplied, it must be a non-empty string
    if args.emptyRB and args.user and (not isinstance(args.user, str) or not args.user.strip()):
        print("Error: --user must be a non-empty string when using --emptyRB.")
        sys.exit(1)
    
    # When using emptyRB, src-profile must be supplied
    if args.emptyRB and not args.src_profile:
        print("Error: --src-profile is required when using --emptyRB.")
        sys.exit(1)

    # When using usermigrate, both src-profile and tgt-profile must be supplied
    if args.usermigrate and (not args.src_profile or not args.tgt_profile):
        print("Error: Both --src-profile and --tgt-profile are required when using --usermigrate.")
        sys.exit(1)

    # When using endpoint export, you cannot use importcheck, foldercheck, or shortcutcheck
    if args.exp and args.endpoint and (args.importcheck or args.foldercheck or args.shortcutcheck):
        print("Error: --importcheck, --foldercheck, and --shortcutcheck cannot be used with --endpoint export.")
        sys.exit(1)

    # When using importcheck, content-path must be supplied
    if args.importcheck and not args.content_path:
        print("Error: --content-path is required when using --importcheck.")
        sys.exit(1)
    
    # When using shortcutcheck, content-path must be supplied
    if args.shortcutcheck and not args.content_path:
        print("Error: --content-path is required when using --shortcutcheck.")
        sys.exit(1)

    # When using foldercheck, content-path or folder-id must be supplied
    if args.foldercheck and not (args.content_path or args.folder_id):
        print("Error: --content-path or --folder-id is required when using --foldercheck.")
        sys.exit(1)

    # When using foldercheck, if both content-path and folder-id are supplied, print a warning and use content-path
    if args.content_path and args.folder_id:
        print("Warning: Both --content-path and --folder-id are supplied. Using --content-path.")
        args.folder_id = None

    # Validate retries is a non-negative integer
    if args.retries < 0:
        print("Error: --retries must be a non-negative integer.")
        sys.exit(1)

#### Generate a unique export name ####
# This function generates a unique export name based on the current date and time.
def generate_export_name(output_path, prefix="Export"):
    # Get the current date and time in UTC
    now = datetime.now(timezone.utc)

    # Format the date and time as YYYY-MM-DD_HHMMSS
    timestamp = now.strftime("%Y-%m-%d_%H%M%S")

    # Remove any characters from the supplied prefix that are not alphanumeric or underscores
    prefix = ''.join(e for e in prefix if e.isalnum() or e == '_')

    # Generate the export name
    export_name = f"{prefix}_{timestamp}"

    # Create the full path for the export file
    export_file_path = os.path.join(output_path, f"{export_name}.json")

    # Ensure the output directory exists
    os.makedirs(output_path, exist_ok=True)

    return export_name, export_file_path

#### Export and Download Package ####
# This function exports content from the source environment and downloads the package.
# Function is passed an export name, export file path, and a list of uris to export.
def export_and_download_package(export_name, export_file_path, uris):
    # Create the export job with the specified name and URIs
    print(f"Creating export job '{export_name}' with {len(uris)} items...")

    export_job_id = create_export_job(export_name, uris)

    if not export_job_id:
        print(f"Failed to create export job for {export_name}.")
        return False

    print(f"Export job created successfully with ID: {export_job_id}")

    # Wait for the export job to complete
    print(f"Waiting for export job {export_job_id} to complete...")

    package_id = wait_export_job(export_job_id)

    if not package_id:
        print(f"Export job {export_job_id} failed or timed out.")
        return False

    print(f"Export job {export_job_id} completed successfully. Package ID: {package_id}")
    
    # Download the exported package
    print(f"Downloading exported package to {export_file_path}...")

    if not download_package(package_id, export_file_path):
        print(f"Failed to download exported package to {export_file_path}.")
        return False
    
    # Delete the package after downloading it
    print(f"Deleting package ID {package_id} after download...")

    if not delete_package(package_id):
        print(f"Failed to delete package ID {package_id}.")
        return False

    print(f"Package ID {package_id} deleted successfully.")

    # If exclude rules is turned on, we need to remove the rules from the export package file manually.
    if args.exclude_rules:
        print(f"Excluding rules from export package {export_file_path}...")
        if not exclude_rules_from_package(export_file_path):
            print(f"Failed to exclude rules from export package {export_file_path}.")
            return False
        print(f"Rules excluded successfully from export package {export_file_path}.")

    return True

#### Upload and Import Package ####
# This function uploads a package to the target environment and imports it.
def upload_and_import_package(package_file):

# Upload the package file to the target environment using the upload package function.
    print(f"Uploading package file {package_file} to target environment {args.tgt_profile}...")

    package_id = upload_package(package_file)

    if not package_id:
        print(f"Failed to upload package file {package_file}.")
        return False

    print(f"Package file {package_file} uploaded successfully with ID: {package_id}")

    # Create an import job for the uploaded package.
    print(f"Creating import job for package ID {package_id} in target environment {args.tgt_profile}...")
    # Generate a unique import job name
    import_name = f"Import_{package_id}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    import_job_id = create_import_job(package_id,import_name)

    if not import_job_id:
        print(f"Failed to create import job for package ID {package_id}.")
        return False

    print(f"Import job created successfully with ID: {import_job_id}")

    # Wait for the import job to complete.
    print(f"Waiting for import job {import_job_id} to complete...")

    wait_import_job(import_job_id)

    return True

def exclude_rules_from_package(export_file_path):
    try:
        # Load the export package JSON file
        with open(export_file_path, 'r', encoding='utf-8') as f:
            package_data = json.load(f)

        # In the export package, there is a transferDetails array with each object having a transferObject and connectors object within it. 
        # Rules can be identitfied by the transferObject.summary.type being "application/vnd.sas.authorization.rule+json".
        # We need to remove any items that are rules, and then update the transferObjectCount number to reflect our new count of transferDetail objects.
        filtered_transfer_details = [
            item for item in package_data.get('transferDetails', []) if item.get('transferObject', {}).get('summary', {}).get('type') != 'application/vnd.sas.authorization.rule+json'
        ]
        package_data['transferDetails'] = filtered_transfer_details

        # Update the transferObjectCount to reflect the new count
        package_data['transferObjectCount'] = len(filtered_transfer_details)

        # Save the updated package data back to the file
        with open(export_file_path, 'w', encoding='utf-8') as f:
            json.dump(package_data, f, ensure_ascii=False, indent=4)

        return True

    except Exception as e:
        print(f"Error excluding rules from package: {e}")
        return False


### End of Support Function Definitions ###

### Intermediate Function Definitions (REST API Calls) ###

#### Get Shortcuts ####
# This function retrieves all shortcuts in a given content path.
# It makes a GET request to /folders/folders/<folderId>/members with the type parameter set to "shortcut".
def get_shortcuts(profile, folder_id):
    # Confirm the folder is not empty before proceeding
    if is_folder_empty(profile, folder_id):
        print(f"Folder {folder_id} is empty. No shortcuts to retrieve.")
        return []

    # Build the request URL
    reqtype = "GET"
    reqval = f"/folders/folders/{folder_id}/members?recursive=true&filter=eq(type,'reference')"
    
    # Make the API call
    response = call_paged_rest_api(profile, reqval, reqtype)

    # The response from call_paged_rest_api should be a list of only shortcut (reference) objects.
    print(f"Retrieved {len(response)} shortcuts from folder {folder_id}.")

    # Print the shortcuts.
    for shortcut in response:
        print(f"Shortcut ID: {shortcut['id']}, Name: {shortcut['name']}, URI: {shortcut['uri']}")
    

#### Get Folder ID ####
# This function retrieves the folder ID for a given content path.
# It makes a GET request to /folders/folders with the content path as a query parameter.
def get_folder_id(profile,content_path):
    # Build the request URL
    reqtype = "GET"
    reqval = f"/folders/folders/@item?path={content_path}"
    
    # Make the API call
    response = callrestapi(profile, reqval, reqtype)

    # The response should include the folder ID
    folder_id = response.get("id")
    
    if not folder_id:
        print(f"Folder ID not found for content path: {content_path}")
        sys.exit(1)

    return folder_id

#### Is Folder Empty ####
# This function checks if a given folder is empty by making a GET request to /folders/folders/<folderId>/members.
# If the response contains an empty items list, the folder is considered empty.
def is_folder_empty(profile, folder_id):
    # Build the request URL
    reqtype = "GET"
    reqval = f"/folders/folders/{folder_id}/members"

    # Make the API call
    response = callrestapi(profile, reqval, reqtype)

    # Check if the items list is empty
    if not response.get("items"):
        return True
    else:
        return False

#### Create Export Job ####
##### This is a POST request to /transfer/exportJobs
##### The body of the request contains an export name and description, an options array and item list.
def create_export_job(ename, items):
    # Build the body of the request
    body = {
        "name": ename,
        "description": f"Export job created by transfer_viya.py for {ename}",
        "options": {
            "includeDependencies": args.include_dependencies,
        },
        "items": items
    }

    reqtype = "POST"
    reqval = "/transfer/exportJobs"

    # Make the API call
    response = callrestapi(args.src_profile,reqval,reqtype,data=body,contentType='application/vnd.sas.transfer.export.request+json')

    # The response should include the job ID
    job_id = response["id"]
    return job_id

##### Wait Export Job ####
##### This is a GET request to /transfer/exportJobs/<jobId> to check the status of the export job.
##### It will keep checking until the job is completed, failed, or a timeout is reached, with a sleep interval between checks.
def wait_export_job(job_id):

    # Set a counter so we don't loop forever. We wait 10 seconds between checks, so the max attempts is timeout / 10
    attempts = 0
    max_attempts = args.timeout // args.wait


    reqtype = "GET"
    reqval = f"/transfer/exportJobs/{job_id}"

    # Call the endpoint to get the current state
    while attempts < max_attempts:
        response = callrestapi(args.src_profile, reqval, reqtype)
        state = response["state"]

        # Possible states: pending, running, completed, failed, canceling, canceled, skipped.
        if state in ["failed", "canceled", "skipped", "canceling"]:
            print(f"Export job {job_id} is in state: {state}")
            return False
        elif state == "completed":
            print(f"Export job {job_id} completed successfully.")
            # The response should have a packageUri attribute in the form /transfer/packages/<packageId>
            package_uri = response.get("packageUri")
            if package_uri:
                package_id = package_uri.split("/")[-1]
                print(f"Export package ID: {package_id}")
                return package_id
            else:
                print("No package URI found in the export job response.")
                return False
        elif state in ["running", "pending"]:
            time.sleep(args.wait)
            attempts += 1
        else:
            print(f"Unexpected state for export job {job_id}: {state}")
            return False
        
    # If we reach here, it means the job did not complete before the timeout was reached.
    print(f"Export job {job_id} did not complete within the timeout.")
    return False

#### Download Export Package ####
##### This is a GET request to /transfer/packages/<packageId> to download the package.
def download_package(package_id, file_path):
    # Define the endpoint to download the package
    reqtype = "GET"
    reqval = f"/transfer/packages/{package_id}"

    # Make the API call
    response = callrestapi(args.src_profile, reqval, reqtype, acceptType='application/vnd.sas.transfer.package+json')

    # The response should be the package content we need to save to a file named export_name in the output_path

    with open(file_path, "w", encoding='utf-8') as f:
        json.dump(response, f, ensure_ascii=False, indent=4)
    
    print(f"Export package downloaded successfully to {file_path}.")
    return file_path

#### Delete Export Package ####
##### This is a DELETE request to /transfer/packages/<packageId> to delete the package.
def delete_package(package_id):
    # Define the endpoint to delete the package
    reqtype = "DELETE"
    reqval = f"/transfer/packages/{package_id}"

    # Make the API call
    callrestapi(args.src_profile, reqval, reqtype)
    
    return True

#### Upload Import Package ####
##### This is a POST request to /transfer/packages to upload the package.
def upload_package(file_path):
    # Read the package content from the file
    with open(file_path, "rb") as f:
        files = { 'file': f }
        reqtype = "MPPOST"
        reqval = "/transfer/packages"

        # Make the API call to upload the package
        response = callrestapi(args.tgt_profile, reqval, reqtype, files=files)

    # The response should include the package ID
    package_id = response["id"]
    print(f"Package uploaded successfully. Package ID: {package_id}")
    return package_id

#### Create Import Job ####
##### This is a POST request to /transfer/importJobs with a JSON body containing the package ID to import.
def create_import_job(package_id, import_name):
    # Build the body of the request
    body = {
        "version": 0,
        "name": import_name,
        "description": f"Import job created by transfer_viya.py for {import_name}",
        "packageUri": f'/transfer/packages/'+package_id
    }
    if args.mapping_file:
        # If a mapping file is supplied, read it and include it in the body
        with open(args.mapping_file, 'r', encoding='utf-8') as f:
            mapping_data = json.load(f)
        body['mapping'] = mapping_data

    reqtype = "POST"
    reqval = "/transfer/importJobs"

    # Make the API call
    response = callrestapi(args.tgt_profile, reqval, reqtype, data=body,contentType='application/vnd.sas.transfer.import.request+json')

    # The response should include the job ID
    job_id = response["id"]
    return job_id

#### Wait Import Job ####
##### This is a GET request to /transfer/importJobs/<jobId> to check the status of the import job.
##### It will keep checking until the job is completed, failed, or a timeout is reached, with a sleep interval between checks.
def wait_import_job(job_id):

    # Set a counter so we don't loop forever
    attempts = 0
    max_attempts = args.timeout // args.wait

    reqtype = "GET"
    reqval = f"/transfer/importJobs/{job_id}"

    # Call the endpoint to get the current state
    while attempts < max_attempts:
        response = callrestapi(args.tgt_profile, reqval, reqtype)
        state = response["state"]

        # Possible states: pending, running, completed, failed, canceling, canceled, skipped.
        if state in ["failed", "canceled", "skipped", "canceling"]:
            print(f"Import job {job_id} is in state: {state}")
            return None
        elif state == "completed":
            print(f"Import job {job_id} completed successfully.")
            return True
        elif state in ["running", "pending"]:
            time.sleep(args.wait)
            attempts += 1
        else:
            print(f"Unexpected state for import job {job_id}: {state}")
            return None
        
    # If we reach here, it means the job did not complete before the timeout was reached.
    print(f"Import job {job_id} did not complete within the timeout.")
    return None

#### Get Child Objects ####
##### This is a GET request to /folders/folders/<folderId>/members?filter=eq(type,'child') to get all child objects in a folder.
def get_child_objects(profile, folder_id):
    # Confirm the folder is not empty before proceeding
    if is_folder_empty(profile, folder_id):
        print(f"Folder {folder_id} is empty. No child objects to retrieve.")
        return []
    # Build the request URL
    reqtype = "GET"
    # if limit is set, add this to the call and don't page through results
    if args.limit:
        reqval = f"/folders/folders/{folder_id}/members?filter=eq(type,'child')&limit={args.limit}"
        response = callrestapi(profile, reqval, reqtype)
        response = response.get('items', [])
    else:
        reqval = f"/folders/folders/{folder_id}/members?filter=eq(type,'child')"
        response = call_paged_rest_api(profile, reqval, reqtype)

    
    print(f"Retrieved {len(response)} child objects from folder {folder_id}.")

    return response

#### Empty Folder ####
# This function is passed a folder id and will delete all child objects in the folder.
# Folder members can be other folders (type=child and contentType=folder), shortcuts (type=reference), or any number of non-folder objects.
# For reference objects, we should only delete the shortcut ('delete' link) and not the target object ('deleteResource' link).
# We should not delete any folders that still have children, so this function will:
# 1. Get all the reference (shortcut) objects in the folder and call the 'delete' link for each one.
# 2. Get all the child objects that are not folders and call the 'deleteResource' link for each one, then the 'delete' link for each one.
# 3. Get all the child objects that are folders use the 'delete' link for each one to dereference them from their parent, then deleteResource to remove them.
# 4. Confirm the folder is now empty.
def empty_folder(folder_id):
    print(f"Emptying folder {folder_id}...")

    # Test if the folder is already empty
    if is_folder_empty(args.src_profile, folder_id):
        print(f"Folder {folder_id} is already empty.")
        return True
    
    # Get all reference (shortcut) objects in the folder
    reqtype = "GET"
    reqval = f"/folders/folders/{folder_id}/members?filter=eq(type,'reference')&recursive=true"
    shortcuts = call_paged_rest_api(args.src_profile, reqval, reqtype)

    # Delete each shortcut using the 'delete' link
    for shortcut in shortcuts:
        if 'links' in shortcut and any(link.get('rel') == 'delete' for link in shortcut['links']):
            delete_link = next(link['href'] for link in shortcut['links'] if link.get('rel') == 'delete')
            print(f"Deleting shortcut {shortcut['name']} (ID: {shortcut['id']}) using link: {delete_link}")
            callrestapi(args.src_profile, delete_link, 'DELETE')

    # Get all child objects that are not folders
    reqval = f"/folders/folders/{folder_id}/members?filter=and(eq(type,'child'),not(eq(contentType,'folder')))&recursive=true"
    child_objects = call_paged_rest_api(args.src_profile, reqval, reqtype)

    # Delete each non-folder child object using the 'deleteResource' link.
    for obj in child_objects:
        if 'links' in obj:
            if any(link.get('rel') == 'deleteResource' for link in obj['links']):
                delete_resource_link = next(link['href'] for link in obj['links'] if link.get('rel') == 'deleteResource')
                print(f"Deleting resource {obj['name']} (ID: {obj['id']}) using link: {delete_resource_link}")
                callrestapi(args.src_profile, delete_resource_link, 'DELETE')

    # Get all remaining child objects (e.g. folders)
    reqval = f"/folders/folders/{folder_id}/members?filter=eq(type,'child')&recursive=true"
    folders = call_paged_rest_api(args.src_profile, reqval, reqtype)

    # Our list of folders will now contain folders that could only contain other folders.
    # To avoid deleting folders that have folder children, we can first loop through all of the folders and use the 'delete' link to derefrence them from their parent.
    # Then, we can delete the folders using the 'deleteResource' link.
    for folder in folders:
        if 'links' in folder and any(link.get('rel') == 'delete' for link in folder['links']):
            delete_link = next(link['href'] for link in folder['links'] if link.get('rel') == 'delete')
            print(f"Dereferencing folder {folder['name']} (ID: {folder['id']}) using link: {delete_link}")
            callrestapi(args.src_profile, delete_link, 'DELETE')
    for folder in folders:
        if 'links' in folder and any(link.get('rel') == 'deleteResource' for link in folder['links']):
            delete_resource_link = next(link['href'] for link in folder['links'] if link.get('rel') == 'deleteResource')
            print(f"Deleting folder {folder['name']} (ID: {folder['id']}) using link: {delete_resource_link}")
            callrestapi(args.src_profile, delete_resource_link, 'DELETE')

    # After all deletions, we should check if the folder is now empty
    print(f"Checking if folder {folder_id} is empty after deletions...")
    # If the folder is empty, we will return True, otherwise we will return False.

    # Confirm the folder is now empty
    if is_folder_empty(args.src_profile, folder_id):
        print(f"Folder {folder_id} is now empty.")
        return True
    else:
        print(f"Folder {folder_id} is not empty after emptying. Please check for remaining objects.")
        return False

### End of Intermediate Function Definitions (REST API Calls) ###

### Validation Function Definitions ###

#### Import Check ####
# This function compares the content of the source and target environments after an import.
# It will check if the items in the source environment exist in the target environment.
# If an item is missing, it will print a warning and return False. If all items are present, it will return True.
def importcheck():
    print("Starting import check...")
    # Get the folder ID from the content path for the source environment
    src_folder_id = get_folder_id(args.src_profile, args.content_path)

    # Get the folder ID from the content path for the target environment
    tgt_folder_id = get_folder_id(args.tgt_profile, args.content_path)

    # Check if either folder is empty. If both are empty we can exit early, if only one is empty then the import check has failed.
    if is_folder_empty(args.src_profile, src_folder_id) and is_folder_empty(args.tgt_profile, tgt_folder_id):
        print("Both source and target folders are empty. No content to check.")
        return True
    elif is_folder_empty(args.src_profile, src_folder_id):
        print(f"Source folder {src_folder_id} is empty. Import check failed.")
        return False
    elif is_folder_empty(args.tgt_profile, tgt_folder_id):
        print(f"Target folder {tgt_folder_id} is empty. Import check failed.")
        return False
    
    # Get the items in the source folder
    reqtype = "GET"
    reqval = f"/folders/folders/{src_folder_id}/members?recursive=true&filter=and(eq(type,'child'),not(eq(contentType,'favoritesFolder')))"
    src_items = call_paged_rest_api(args.src_profile, reqval, reqtype)
    print(f"Retrieved {len(src_items)} items from source folder {src_folder_id}.")

    # Get the items in the target folder
    reqval = f"/folders/folders/{tgt_folder_id}/members?recursive=true&filter=and(eq(type,'child'),not(eq(contentType,'favoritesFolder')))"
    tgt_items = call_paged_rest_api(args.tgt_profile, reqval, reqtype)
    print(f"Retrieved {len(tgt_items)} items from target folder {tgt_folder_id}.")

    # We only need to compare the name of each item, as the ID may be different in the target environment.
    src_item_names = {item["name"]: item for item in src_items}
    tgt_item_names = {item["name"]: item for item in tgt_items}
    
    # Compare the items in the source and target folders
    missing_items = [item for name, item in src_item_names.items() if name not in tgt_item_names]

    # If there are missing items, print a warning and return False
    if missing_items:
        print(f"Import check failed, source and target folders do not match.")
        if args.verbose:
            print(f"The following items are missing in the target environment:")
            for item in missing_items:
                print(f"- {item['name']} (ID: {item['id']})")
        return False
    
    # If all items are present, return True
    print("Import check passed. All items are present in the target environment.")
    return True
        
#### Export Check ####
# This function checks if the export package contains connections for exported objects and, if a folder ID is provided, checks that all the items in the folder are in the export package.
def exportcheck(package_file, folder_id=None):
    print("Starting export check...")
    # Load the export package from the file
    with open(package_file, "r", encoding='utf-8') as f:
        package = json.load(f)

    # Get the parent folders defined in the export package
    # The transferDetails array of the export package contains each object that was exported. The connectors array includes a type "parentFolder"
    # for each object. As a parentFolder could be connected to multiple objects, we need to only capture it into a list once.
    
    # First output a unique list of the parent folder name and uri values
    parent_folders = []
    for item in package["transferDetails"]:
        for connector in item["connectors"]:
            if connector["type"] == "parentFolder":
                parent_folder = {
                    "name": connector["name"],
                    "uri": connector["uri"]
                }
                if parent_folder not in parent_folders:
                    parent_folders.append(parent_folder)

    # Print the number of parent folders found in the export package
    print(f"Found {len(parent_folders)} parent folders in the export package.")

    # Print the list of parent folders found in the export package
    if args.verbose:
        print("The following parent folders were found in the export package:")
        for folder in parent_folders:
            print(f"  - {folder['name']} ({folder['uri']})")
        print("")

   # The export package file is a JSON file that has a transferDetails top level array that contains
    # the details of each object that was exported. Each object in the transferDetails array has a 
    # transferObject object that contains a summary object that contains a links array whose link
    # with rel "self" contains the uri of the object. 

    # We need to confirm each parent folder URI we captured from the connectors array also has a transferObject
    # for itself. If the package does not contain a transferObject for the parent folder, this will cause 
    # the import to put the object in the wrong location.

    # We will iterate through the parent folders and check if each one has a transferObject in the export package.

    for folder in parent_folders:
        # Check if the folder has a transferObject in the export package
        found = False
        for item in package["transferDetails"]:
            if "transferObject" in item and "summary" in item["transferObject"]:
                if "links" in item["transferObject"]["summary"]:
                    for link in item["transferObject"]["summary"]["links"]:
                        if link["rel"] == "self" and link["uri"] == folder["uri"]:
                            found = True
                            break
            if found:
                break

        # If the folder does not have a transferObject, print an error message
        if not found:
            print(f"ERROR: Parent folder {folder['name']} ({folder['uri']}) does not have a transferObject in the export package.")
            print("This will cause the import to put the object in the wrong location.")
            return False
        
    # If no folder ID is provided, we can stop here and return True. If we do have a folder ID, we need to 
    # get a recursive list of members of type child from the folder ID, and confirm each child object is present
    # in the export package. We will use the /folders/folders/id/members endpoint to get the members of the folder ID.
    if folder_id is None:
        print("No folder ID provided. Skipping check for child objects.")
        return True

    # Pull a recursive list of members of type child from the folder ID
    reqtype = "GET"
    reqval = f"/folders/folders/{folder_id}/members?recursive=true&filter=and(eq(type,'child'),not(eq(contentType,'application/vnd.sas.analytics.localization.context')))"
    folder_items = call_paged_rest_api(args.src_profile, reqval, reqtype)

    # Print the number of child items found in the folder ID
    print(f"Found {len(folder_items)} child items in folder ID {folder_id}.")

    # Now our folder_items list contains all the uris of the child objects in the folder ID.
    # We need to confirm all of these uris are present in the export package.
    # We will store the uris of the objects folder ID that are not in the export package.
    
    missing_items = {item["uri"] for item in folder_items}

    for item in package["transferDetails"]:
        if "transferObject" in item and "summary" in item["transferObject"]:
            if "links" in item["transferObject"]["summary"]:
                for link in item["transferObject"]["summary"]["links"]:
                    if link["rel"] == "self":
                        # If the uri is in the export package, remove it from the missing items set
                        if link["uri"] in missing_items:
                            missing_items.remove(link["uri"])

    # If there are any missing items, we will print them out
    if len(missing_items) > 0:
        print(f"The following items are missing from the export package:")
        for item in missing_items:
            print(f"  - {item}")
        return False
    # If there are no missing items, we will print a message saying so
    else:
        print(f"All items in the folder ID {folder_id} are present in the export package.")
        print("No missing items found.")
        return True

#### Folder Check ####
# This function checks a given folder ID for child members and performs a HEAD request on each member to ensure they exist.
def foldercheck(folder_id):

    print(f"Starting folder check for folder ID: {folder_id}")
    
    # Check if the folder is empty
    if is_folder_empty(args.src_profile, folder_id):
        print(f"Folder {folder_id} is empty. No content to check.")
        return True

    # Get the members of the folder
    reqtype = "GET"
    reqval = f"/folders/folders/{folder_id}/members?recursive=true&filter=eq(type,'child')"
    members = call_paged_rest_api(args.src_profile, reqval, reqtype)
    
    print(f"Retrieved {len(members)} members from folder {folder_id}.")

    # Check if there are any members in the folder
    if not members:
        print(f"Folder {folder_id} has no child members.")
        return True
    
    foldercheckfailed = False

    for member in members:
        # Retrieve the getResource rel link from the member
        resource_link = next((link['href'] for link in member.get('links', []) if link.get('rel') == 'getResource'), None)
        if not resource_link:
            print(f"Member {member['name']} (ID: {member['id']}) does not have a getResource link.")
            continue
        
        # Perform a HEAD request on the resource link
        reqtype = "HEAD"
        response, status_code = callrestapi(args.src_profile, resource_link, reqtype)

        # If the status is 404, the resource does not exist. If delete is set we should remove that member from the folder. If not we should print a warning and move to the next member.
        if status_code == 404:
            foldercheckfailed = True
            print(f"Member {member['name']} (ID: {member['id']}) does not exist in the source environment.")
            if args.delete:
                print(f"Member {member['name']} (ID: {member['id']}) will be deleted from folder {folder_id} in the source environment.")
                # If delete is set, we need to get the delete rel link from the member and perform a DELETE request on it
                delete_link = next((link['href'] for link in member.get('links', []) if link.get('rel') == 'delete'), None)
                if delete_link:
                    reqtype = "DELETE"
                    callrestapi(args.src_profile, delete_link, reqtype)
                    print(f"Deleted member {member['name']} (ID: {member['id']}) from folder {folder_id}.")
                    foldercheckfailed = False
                else:
                    print(f"Member {member['name']} (ID: {member['id']}) does not have a delete link.")
            else:
                print(f"Warning: Member {member['name']} (ID: {member['id']}) does not exist in the source environment and --delete option not specified.")
                print(f"Warning: Run the script with --delete to remove this member from the folder {folder_id} in the source environment.")
                print(f"Warning: You can also manually make a DELETE request to {delete_link} to remove this member from the folder {folder_id}.")
        else:
            if args.verbose:
                print(f"Member {member['name']} (ID: {member['id']}) exists in the source environment.")

    if foldercheckfailed:
        return False
    else:
        print(f"Folder check for folder ID {folder_id} passed. All members exist in the source environment.")
        return True

#### End of Validation Function Definitions ###

### Main Function Definitions ###
#### Export ####
# This function could be called with either a content path or an endpoint.
# If a content path is provided, it will get the folder ID for the content path and then get all child objects in the folder.
# It will then create an export job for each child object, wait for the job to complete, and download the export package to the specified output path.
# If an endpoint is provided, it will call the endpoint to get the list of objects to export.
# It will then create an export job for every chunksize number of objects, wait for the job to complete, and download the export package to the specified output path.
# If called with the validation functions it will perform those validations either before or after exporting as appropriate.
# If called with the import option it will also upload the exported package to the target environment and create an import job for it, then wait for it to complete.
def export():
    print("Starting export...")
    
    # Confirm the output path exists and we can write to it
    if not os.path.exists(args.output_path):
        print(f"Error: Output path {args.output_path} does not exist.")
        sys.exit(1)
    if not os.access(args.output_path, os.W_OK):
        print(f"Error: Output path {args.output_path} is not writable.")
        sys.exit(1)

    # If a content path is provided, make sure it isn't empty
    if args.content_path:
        folder_id = get_folder_id(args.src_profile, args.content_path)
        if is_folder_empty(args.src_profile, folder_id):
            print(f"Error: Content path {args.content_path} is empty.")
            sys.exit(1)

    # Create a directory in the output path named Export_<datetime> to store the export packages
    export_dir = os.path.join(args.output_path, f"Export_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
    os.makedirs(export_dir, exist_ok=True)
    print(f"Export directory created: {export_dir}")

    # We need to diverge here depending on whether we are using a content path or an endpoint
    if args.content_path:
        # Get the folder ID for the content path
        folder_id = get_folder_id(args.src_profile, args.content_path)

        # Get all child objects in the folder
        items = get_child_objects(args.src_profile, folder_id)
    
        # For each item, we need to create an export job, wait for it to complete, and download the export package
        for item in items:

            if item['contentType'] == 'folder' or 'Folder' in item['contentType']:
                # Get the folder ID from the folder membership item's uri attribute
                folder_id = item['uri'].split('/')[-1]

            # Before we export the item, if it is a folder, we should run our folder specific validations if requested.
            if item['contentType'] == 'folder' or 'Folder' in item['contentType']:
                folder_check_successful = True
                if args.foldercheck:                    
                    print(f"Running folder check for folder: {item['name']} (ID: {folder_id})")
                    folder_check_successful = foldercheck(folder_id)
                if args.shortcutcheck:
                    print(f"Running shortcut check for folder: {item['name']} (ID: {folder_id})")
                    get_shortcuts(args.src_profile, folder_id)
                # Only export if the folder check was successful or if we are not running folder checks
                if not folder_check_successful and args.foldercheck:
                    print(f"Skipping export for folder {item['name']} (ID: {folder_id}) due to folder check failure.")
                    continue
            print(f"Creating export job for item: {item['name']} (URI: {item['uri']})")
            # Generate a unique export name for the item
            
            export_name, export_file_path = generate_export_name(export_dir, prefix=item['name'])
            # export and download the package for the item
            print(f"Exporting item: {item['name']} (URI: {item['uri']}) to {export_file_path}")
            if export_and_download_package(export_name, export_file_path, [ item['uri'] ]) is False:
                print(f"Error: Export job for item {item['name']} (URI: {item['uri']}) failed.")
                continue
            
            # If we have exportcheck enabled, we will run the export check after each export
            # If it's a folder we should pass the id of the folder to the exportcheck function, otherwise we should not, but still run the exportcheck function
            if args.exportcheck:
                print(f"Running export check for item: {item['name']} (ID: {item['uri']})")

                # If the content type contains the word 'folder', we will pass the folder_id to the exportcheck function
                
                if item['contentType'] == 'folder' or 'Folder' in item['contentType']:
                    export_check_successful = exportcheck(export_file_path, folder_id)
                else:
                    export_check_successful = exportcheck(export_file_path)
                if not export_check_successful:
                    print(f"Export check failed for item: {item['name']} (ID: {item['uri']}). Deleting export package.")
                    # Delete the export package if the export check failed
                    os.remove(export_file_path)
                    # We need to retry the export when it fails up to args.retries times. If it fails after that we will skip the item and move on to the next one.
                    retries = 0
                    while retries < args.retries:
                        print(f"Retrying export for item: {item['name']} (ID: {item['uri']}). Attempt {retries + 1} of {args.retries}.")
                        export_name, export_file_path = generate_export_name(export_dir, prefix=item['name'])
                        if export_and_download_package(export_name, export_file_path, [ item['uri'] ]) is False:
                            print(f"Error: Export job for item {item['name']} (URI: {item['uri']}) failed.")
                            retries += 1
                            continue
                        # Run the export check again
                        if item['contentType'] == 'folder' or 'Folder' in item['contentType']:
                            export_check_successful = exportcheck(export_file_path, folder_id)
                        else:
                            export_check_successful = exportcheck(export_file_path)
                        if not export_check_successful:
                            print(f"Export check failed for item: {item['name']} (ID: {item['uri']}). Deleting export package.")
                            os.remove(export_file_path)
                            retries += 1
                            continue
                        else:
                            print(f"Export check passed for item: {item['name']} (ID: {item['uri']}) on retry attempt {retries + 1}.")
                            break
                else:
                    print(f"Export check passed for item: {item['name']} (ID: {item['uri']})")
            
            # If we have import enabled, we will upload the export package to the target environment and create an import job for it
            if args.imp:
                print(f"Uploading export package for item: {item['name']} (ID: {item['uri']}) to target environment.")

                if upload_and_import_package(export_file_path):
                    print(f"Import of {export_name} completed successfully.")
                else:
                    print(f"Import of {export_name} failed.")
                
        # If we have importcheck enabled, we will run the import check after all exports and imports are done
        if args.importcheck and args.imp:
            print("Running import check after all exports and imports.")
            import_check_successful = importcheck()
            if not import_check_successful:
                print("Import check failed. Some items are missing in the target environment.")
            else:
                print("Import check passed. All items are present in the target environment.")
            
    elif args.endpoint:

        # Call the endpoint to get the list of objects to export
        reqtype = "GET"
        if args.limit:
            reqval = f"{args.endpoint}?limit={args.limit}"
            response = callrestapi(args.src_profile, reqval, reqtype)
            # set response to be the items array from the response
            response = response.get('items', [])
        else:
            reqval = args.endpoint
            response = call_paged_rest_api(args.src_profile, reqval, reqtype)

        # For each chunksize number of objects, we need to create an export job, wait for it to complete, and download the export package
        chunk = []
        count = 0
        expcount = 1
        for item in response:
            # Add to the chunk uri from the "self" link of the item
            if 'links' in item and any(link.get('rel') == 'self' for link in item['links']):
                self_link = next(link['href'] for link in item['links'] if link.get('rel') == 'self')
                item['uri'] = self_link
            else:
                print(f"Warning: Item {item['name']} does not have a self link. Skipping.")
                continue
            
            chunk.append( item['uri'] )
            count += 1
            if count == args.chunksize:
                print(f"Creating export job for {args.chunksize} items...")

                # Generate a prefix for generate_export_name based on the endpoint and chunk number.
                prefix = f"{args.endpoint.split('/')[-1]}_chunk_{expcount}"
                
                export_name, export_file_path = generate_export_name(export_dir, prefix=prefix)
                # Create the export job and download the package
                export_result = export_and_download_package(export_name, export_file_path, chunk)
                
                chunk = []
                count = 0
                expcount += 1
                if not export_result:
                    print(f"Error: Export job for chunk failed.")
                    continue
                # If we have exportcheck enabled, we will run the export check after each export
                if args.exportcheck:
                    print(f"Running export check for chunk {expcount}...")
                    export_check_successful = exportcheck(export_file_path)
                    if not export_check_successful:
                        print(f"Export check failed for chunk {expcount}. Deleting export package.")
                        # Delete the export package if the export check failed
                        os.remove(export_file_path)
                        # We need to retry the export when it fails up to args.retries times. If it fails after that we will skip the chunk and move on to the next one.
                        retries = 0
                        while retries < args.retries:
                            print(f"Retrying export for chunk {expcount}. Attempt {retries + 1} of {args.retries}.")
                            export_name, export_file_path = generate_export_name(export_dir, prefix=prefix)
                            if export_and_download_package(export_name, export_file_path, chunk) is False:
                                print(f"Error: Export job for chunk {expcount} failed.")
                                retries += 1
                                continue
                            # Run the export check again
                            export_check_successful = exportcheck(export_file_path)
                            if not export_check_successful:
                                print(f"Export check failed for chunk {expcount}. Deleting export package.")
                                os.remove(export_file_path)
                                retries += 1
                                continue
                            else:
                                print(f"Export check passed for chunk {expcount} on retry attempt {retries + 1}.")
                                break
                    else:
                        print(f"Export check passed for chunk {expcount}.")
                # If imp is enabled, we will upload the export package to the target environment and create an import job for it
                if args.imp:
                    print(f"Uploading export package for chunk to target environment.")
                    if upload_and_import_package(export_file_path):
                        print(f"Import job for chunk completed successfully.")
                    else:
                        print(f"Import job for chunk failed.")
                else:
                    print(f"Export package for chunk downloaded successfully to {export_file_path}.")
        
        # If there are any remaining items in the chunk, we need to create an export job for them as well
        if chunk:
            print(f"Creating export job for {len(chunk)} items...")
            prefix = f"{args.endpoint.split('/')[-1]}_chunk_{expcount}"
            export_name, export_file_path = generate_export_name(export_dir, prefix=prefix)
            if export_and_download_package(export_name, export_file_path, chunk):
                print(f"Export package for chunk downloaded successfully to {export_file_path}.")
                if args.exportcheck:
                    print(f"Running export check for chunk {expcount}...")
                    export_check_successful = exportcheck(export_file_path)
                    if not export_check_successful:
                        print(f"Export check failed for chunk {expcount}. Deleting export package.")
                        # Delete the export package if the export check failed
                        os.remove(export_file_path)
                        # We need to retry the export when it fails up to args.retries times. If it fails after that we will skip the chunk and move on to the next one.
                        retries = 0
                        while retries < args.retries:
                            print(f"Retrying export for chunk {expcount}. Attempt {retries + 1} of {args.retries}.")
                            export_name, export_file_path = generate_export_name(export_dir, prefix=prefix)
                            if export_and_download_package(export_name, export_file_path, chunk) is False:
                                print(f"Error: Export job for chunk {expcount} failed.")
                                retries += 1
                                continue
                            # Run the export check again
                            export_check_successful = exportcheck(export_file_path)
                            if not export_check_successful:
                                print(f"Export check failed for chunk {expcount}. Deleting export package.")
                                os.remove(export_file_path)
                                retries += 1
                                continue
                            else:
                                print(f"Export check passed for chunk {expcount} on retry attempt {retries + 1}.")
                                break
                    else:
                        print(f"Export check passed for chunk {expcount}.")
                # If imp is enabled, we will upload the export package to the target environment and create an import job for it
                if args.imp:
                    print(f"Uploading export package for chunk to target environment.")
                    
                    if upload_and_import_package(export_file_path):
                        print(f"Import job for chunk completed successfully.")
                    else:
                        print(f"Import job for chunk failed.")
            else:
                print(f"Error: Export job for chunk failed.")

#### Import ####
# This function is passed a file path that contains one or more export packages.
# It will upload each package to the target environment and create an import job for it.
# It will then wait for the import job to complete and return the status of the import.
def import_packages():
    print("Starting import...")
    
    # Confirm the import path exists and we can read from it
    if not os.path.exists(args.import_path):
        print(f"Error: Import path {args.import_path} does not exist.")
        sys.exit(1)
    if not os.access(args.import_path, os.R_OK):
        print(f"Error: Import path {args.import_path} is not readable.")
        sys.exit(1)
    
    # Get export packages from the import path
    export_packages = [f for f in os.listdir(args.import_path) if f.endswith('.json')]
    if not export_packages:
        print(f"Error: No export packages found in import path {args.import_path}.")
        sys.exit(1)
    
    # For each file in the import path, run upload_and_import_package
    for package_file in export_packages:
        package_path = os.path.join(args.import_path, package_file)
        print(f"Processing export package: {package_path}")
        
        # Upload the export package to the target environment and create an import job for it
        if upload_and_import_package(package_path):
            print(f"Import job for {package_file} completed successfully.")
        else:
            print(f"Import job for {package_file} failed.")

#### User Migration ####
# This function pulls all the users from the source environment's /SASLogon/Users and creates them 
# in the target environment if they do not exist.
def usermigrate():

    # From the source environment, call /SASLogon/Users to get all the shadow IDs (users who have logged in to the source environment)
    # We will use the query parameter attributes=id,userName to get a list of all the IDs and user names from the source.

    # The response is a JSON object with an array "resources" containing the user objects. There is also a totalResults key 
    # that tells us how many users there are. If we don't get the full total on the first request, we will use this to iterate
    # through the users by incrementing the startIndex by the size of the resources array
    # We should omit the username "sasboot" from the list of users to be migrated, but increment the startIndex by the size
    # of the resource array without this ommission.

    # Pull the first set of results from /SASLogon/Users?attributes=id,userName
    # We will use the headers to set the Accept and Authorization headers.

    url = f"/SASLogon/Users?attributes=id,userName"

    reqtype = "GET"
    reqval = url
    response = callrestapi(args.src_profile, reqval, reqtype)

    users = response["resources"]
    total_results = response["totalResults"]
    start_index = len(users) + 1

    # If there are more users to get, we will loop through the results until we get all the users
    while len(users) < total_results:
        
        reqval=url + f"&startIndex={start_index}"
        response = callrestapi(args.src_profile, reqval, reqtype)
        
        users += response["resources"]
        start_index += len(response["resources"])
        if start_index > total_results:
            break

    # We now have a list of all the users in the source environment. We need to iterate through the list to see 
    # if they exist in the target environment, omitting the user "sasboot". This will be done by calling /SASLogon/Users?filter=userName eq '<username>'
    # for each user we found in the source environment against the target environment. This will return a 200 even if no users are found
    # but we can use the totalResults key to see if it found anyone. 

    # If the user is not found in the target environment, we will call /SASLogon/Users/id on the source environment to get the user object
    # from the source and remove the keys we don't need (.approvals,.groups,.id,.meta,.zoneId,.passwordLastModified,.previousLogonTime,.lastLogonTime)
    # then POST it to the target environment using /SASLogon/Users
    
    # For each user in the users array, we will check if the user is "sasboot" and skip it if it is
    # If the user is not "sasboot", we will check if the user exists in the target environment
    # If the user exists, we will skip it
    # If the user does not exist, we will get the user object from the source environment and remove the keys we don't need
    # and POST it to the target environment

    for user in users:
        if user["userName"] == "sasboot":
            continue
        # Check if the user exists in the target environment
        reqtype = "GET"
        reqval = f"/SASLogon/Users?filter=userName eq '{user['userName']}'"

        response = callrestapi(args.tgt_profile, reqval, reqtype)

        if response["totalResults"] > 0:
            print(f"User {user['userName']} already exists in target environment.")
            continue
        # If the user does not exist, get the user object from the source environment
        reqval = f"/SASLogon/Users/{user['id']}"
        response = callrestapi(args.src_profile, reqval, reqtype)

        # Remove the keys we don't need if they exist
        if "approvals" in response:
            del response["approvals"]
        if "groups" in response:
            del response["groups"]
        if "id" in response:
            del response["id"]
        if "meta" in response:
            del response["meta"]
        if "zoneId" in response:
            del response["zoneId"]
        if "passwordLastModified" in response:
            del response["passwordLastModified"]
        if "previousLogonTime" in response:
            del response["previousLogonTime"]
        if "lastLogonTime" in response:
            del response["lastLogonTime"]
        
        # POST the user object to the target environment
        reqtype = "POST"
        reqval = f"/SASLogon/Users"
        response = callrestapi(args.tgt_profile, reqval, reqtype, data=response)
        print(f"User {user['userName']} created successfully in target environment.")

#### Empty Recycle Bin ####
# This function empties the recycle bin for a given user or all users in the source environment.
# All Recycle bins can be retrieved from /folders/folders?filter=eq(type, 'trashFolder'). For a single user,
# we can find their user folder (/Users/<username>) and pull it's members where 'contentType' is 'trashFolder'.
# A Recycle bin folder does not have a special empty link, so we would need to delete each item using our empty folder function.
def empty_recycle_bins(username=None):
    print("Starting to empty recycle bins...")

    # If we are given a username, we will get the user folder for that user
    if username:
        print(f"Emptying recycle bin for user: {username}")
        user_folder_id = get_folder_id(args.src_profile, f"/Users/{username}")
        if not user_folder_id:
            print(f"Error: User folder for {username} not found.")
            return False
        print(f"User folder ID for {username} is {user_folder_id}")

        # Get the recycle bin for the user
        reqtype = "GET"
        reqval = f"/folders/folders/{user_folder_id}/members?filter=eq(contentType,'trashFolder')"
        recycle_bins = call_paged_rest_api(args.src_profile, reqval, reqtype)


    else:
        # If no username is provided, we will get all recycle bins for all users
        reqtype = "GET"
        reqval = "/folders/folders?filter=eq(type,'trashFolder')"
        recycle_bins = call_paged_rest_api(args.src_profile, reqval, reqtype)

    # If no recycle bins are found, we can exit early
    if not recycle_bins:
        print("No recycle bins found.")
        return True
    
    # Iterate through each recycle bin and empty it
    for recycle_bin in recycle_bins:
        # The recycle_bin object's ID is not the folder ID but the ID of the membership in the parent folder.
        # We need to get the actual folder ID from the 'uri' attribute of the object.
        recycle_bin_folder_id = recycle_bin['uri'].split('/')[-1]
        print(f"Emptying recycle bin: {recycle_bin['name']} (ID: {recycle_bin_folder_id})")
        if empty_folder(recycle_bin_folder_id):
            print(f"Recycle bin {recycle_bin['name']} (ID: {recycle_bin_folder_id}) emptied successfully.")
        else:
            print(f"Error: Failed to empty recycle bin {recycle_bin['name']} (ID: {recycle_bin_folder_id}).")
    
    return True

### End of Main Function Definitions ###

### Main Script Logic ###
if __name__ == "__main__":
    
    # Validate the options
    validate_options()

    # If the usermigrate option is set, call the usermigrate function
    if args.usermigrate:
        usermigrate()
    
    # If the emptyRB option is set, call the empty_recycle_bins function
    if args.emptyRB:
        if args.user:
            empty_recycle_bins(username=args.user)
        else:
            empty_recycle_bins()

    # If only exportcheck is set, call the exportcheck function
    if args.exportcheck and not args.exp:
        exportcheck(args.export_file, args.folder_id)

    # If only importcheck is set, call the importcheck function
    if args.importcheck and not args.imp:
        importcheck()

    # If only foldercheck is set, call the foldercheck function
    if args.foldercheck and not args.exp:
        # If a content path is provided, get the folder ID from it
        if args.content_path:
            folder_id = get_folder_id(args.src_profile, args.content_path)
        else:
            folder_id = args.folder_id
        foldercheck(folder_id)

    # If only shortcutcheck is set, call the get_shortcuts function
    if args.shortcutcheck and not args.exp:
        # If a content path is provided, get the folder ID from it
        if args.content_path:
            folder_id = get_folder_id(args.src_profile, args.content_path)
        else:
            folder_id = args.folder_id
        get_shortcuts(args.src_profile, folder_id)
    
    # If the import option is set without the export option, call the import_packages function
    if args.imp and not args.exp:
        import_packages()

    # If the export option is set, call the export function
    if args.exp:
        export()

    # If we reach here, we have successfully completed the script
    print("Script completed successfully.")
    sys.exit(0)