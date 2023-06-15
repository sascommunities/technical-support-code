/******************************************************************************/
/* This program will connect to Metadata and change the stored password for   */
/* the user who is connecting or for an admin user, the user specified.       */
/* The latter requires using the commented queries in the code.               */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 21OCT2019                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Metadata Connection information. */
%let user=sasdemo;
%let pass=pass1;
%let host=meta.demo.sas.com;
%let port=8561;

/* Provide information to identify the Login to be updated, and the new password. */

%let authdomain=DefaultAuth;
 *%let uname=sasdemo; /* Uncomment this if you want to use the query below that allows you to specify a user id to search for. To use this you must also switch the queries in two places below. */
%let newpass=Orion123;


/* Establish a connection to the Metadata Server. */
options metaserver="&host"
		metaport=&port
		metauser="&user"
		metapass="&pass"
		metarepository=Foundation
		metaprotocol=BRIDGE;

/* This data step performs the queries against Metadata to confirm the existence of the object and then attempt to update the password. */

data _null_;
	length id type $ 50;
	call missing (of _character_);

	/* This query looks for a Login object with a User ID equal to the uname value specified above that is a member of the Authentication Domain specified above.*/
	/* Uncomment this query and comment out the one below it to use. */
	*obj="omsobj:Login?Login[@UserId = '"||"&uname"||"'][Domain/AuthenticationDomain[@Name = '"||"&authdomain"||"']]"; 

	/* This query will search for any login for the supplied domain, so a normal user should only find themselves. */
	obj="omsobj:Login?Login[Domain/AuthenticationDomain[@Name = '"||"&authdomain"||"']]";
	put "NOTE:Object Query definition is " obj;
	login_count=metadata_resolve(obj,type,id);
	if login_count = -1 then do;
		put "ERROR: Failed to connect to the Metadata Server. Check your connection information.";
		abort cancel;
	end;

	put "NOTE: Found " login_count "logins";

 	/* Only move forward if only one login is found that matches the query, so we avoid updating the wrong object. */
	if login_count = 1 then do;
	objid=cats(type,"/",id);
	put "NOTE: Resetting password for Object: " objid=;

	/* This is the command that sets the password attribute. */
	rc=metadata_setattr(objid,"Password","&newpass");

	/* Interpret the return code to the log. */
	put "NOTE: Password change RC is " rc=;
		if rc = 0 then do;
		 put "NOTE: Password change was successful.";
		end;
		else if rc = -1 then do;
		 put "ERROR: Unable to connect to Metadata Server. This section of the code is hit after successfully connecting to Metadata, so this should not happen.";
		end;
		else if rc = -2 then do;
		 put "ERROR: Unable to set the attribute. This is probably a role / permission issue.";
		end;
		else if rc = -3 then do;
		 put "ERROR: No objects match the URI. This URI was built from another response so this should not happen.";
		end;
	end;
	else do; 
		put "ERROR: Query parameters did not return only 1 login. If you are not already, you may wish to try specifying a user ID.";
		abort cancel;
		end;
run;

/* Retrieve the password stored and set it to a macro variable. */

data _null_;
	length passval $ 255;
	call missing (of _character_);

	/* This query looks for a Login object with a User ID equal to the uname value specified above that is a member of the Authentication Domain specified above.*/
	/* Uncomment this query and comment out the one below it to use. */
	*obj="omsobj:Login?Login[@UserId = '"||"&uname"||"'][Domain/AuthenticationDomain[@Name = '"||"&authdomain"||"']]"; 

	obj="omsobj:Login?Login[Domain/AuthenticationDomain[@Name = '"||"&authdomain"||"']]";
	rc=metadata_getattr(obj,"Password",passval);
	if passval ="{SAS002}B6535B5C02BB1BC110FD31944FC989D3" then do;
		/* Throw an error if we are returned the encoded version of "*******" */
		put "WARNING: You are logged in as a user with the unrestricted or user administration metadata role.";
		put "WARNING: I cannot validate the password was set correctly as all passwords are returned to you as '********'";
		put "WARNING: Stopping validation process.";
		abort cancel;
	end;
	/* Put the retrieved password into a macro variable. */
	call symput('retpass',passval);
run;

data _null_;
	newpassprefix=substr("&newpass",1,4);
	if newpassprefix="{SAS" then do;
	put "NOTE: New password was supplied encoded, setting this value to _PWENCODE variable for validation.";
	call symput('_PWENCODE',"&newpass");
	end;
run;

/* Encode the password provided (this will populate _PWENCODE with the encoded password). */
proc pwencode in="&newpass"; run;

/* Check if the returned and encoded passwords match. */
data _null_;
	retpass=symget("retpass");
	put retpass=;
	encpass=symget("_PWENCODE");
	put encpass=;
	if retpass=encpass then do;
	put "NOTE: Confirmed new password is now stored in Metadata.";
	end;
	/* Throw an error if the passwords don't match. */
	else put "ERROR: Checking stored password against the value specified did not match.";
run;

/* Reset variables. */
data _null_;
	%symdel user pass host port authdomain uname newpass retpass _PWENCODE;
run;

%put _global_;
