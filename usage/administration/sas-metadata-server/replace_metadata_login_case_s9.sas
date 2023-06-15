/******************************************************************************/
/* This program will convert all logins for a given authetnication domain to  */
/* lowercase.                                                                 */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 23JAN2023                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/** This program will convert all logins for a given authentication domain to lowercase. **/
/* Author: Greg Wootton Date: 23JAN2023 */

/* Metadata connection information: */

%let metaserve=meta.demo.sas.com;
%let metaport=8561;
%let userid=sasadm@saspw;
%let pass=Password;

/* The authentication domain we want to convert all userids case */
%let authdom=DefaultAuth;

/* End edit. */

/* Connect to Metadata Server */

options	metaserver="&metaserve"
		metaport=&metaport
		metauser="&userid"
		metapass="&pass"
		metarepository=Foundation
		metaprotocol=BRIDGE;

data _null_;

/* Initialize variables */
length type $ 5 id $ 17 login_uri $ 30 uid lowcase $ 255;
call missing (of _character_);

/* Define a query to find all logins for a given authdomain */
obj="omsobj:Login?Login[Domain/AuthenticationDomain[@Name = '"||"&authdom"||"']]";

/* Count how many logins match that query. */
login_count=metadata_resolve(obj,type,id);

/* Fail if we can't connect to Metadata. */
if login_count = -1 then do;
  put "ERROR: Failed to connect to the Metadata Server. Check your connection information.";
  abort cancel;
end;

/* Write out how many logins we found. */
put "NOTE: Found " login_count "logins";

/* If we found any logins, iterate through them. */
if login_count > 0 then do i=1 to login_count;

    /* Get the URI for the nth login. */
	rc=metadata_getnobj(obj,i,login_uri);

    /* Get the UserId for the nth login. */
	rc=metadata_getattr(login_uri,"UserId",uid);

    /* Convert to lowercase. */
	lowcase=lowcase(uid);

    if lowcase = uid then put "NOTE: UserId is already lowercase: " uid=;
    else do;
        put "NOTE: I want to change " uid "to " lowcase;
        /* Uncomment this section to actually make the change. */
        /*rc=metadata_setattr(login_uri,"UserId",lowcase);*/
        /* if rc = 0 then do;
            put "NOTE: UserID change was successful.";
        end;
        else if rc = -1 then put "ERROR: Unable to connect to Metadata Server. This section of the code is hit after successfully connecting to Metadata, so this should not happen.";
        else if rc = -2 then put "ERROR: Unable to set the attribute. This is probably a role / permission issue.";
        else if rc = -3 then put "ERROR: No objects match the URI. This URI was built from another response so this should not happen."; */
    end;
end;

run;