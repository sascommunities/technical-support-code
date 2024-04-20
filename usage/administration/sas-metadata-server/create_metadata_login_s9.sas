/******************************************************************************/
/* This macro creates a Login object and associates it with the designated    */
/* metadata user and authdomain.                                              */
/* Date: 18APR2024                                                            */
/******************************************************************************/

/* Copyright © 2024, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved. */
/* SPDX-License-Identifier: Apache-2.0 */

/* Define Metadata connection information */

options metaserver="meta.example.com"   /* TODO: Set to your metadata server host */
		metaport=8561 
		metauser="sasadm@saspw"
		metapass="sasadm@saspw password"    /* TODO: Set to your sasadm@saspw password */
		metarepository=Foundation
		metaprotocol=BRIDGE;

/* the following macro definition can be stored in the sasautos concatenation */
/* or defined in your program.  Once defined, it can be executed using the    */
/* named parameters in a manner such as this:                                 */
/*
%createLoginObject(
  Person_Name=sasdemo, 
  Authdomain=OracleAuth,
  Login_userid=scott,
  Login_password=tiger,
  Login_name=sasdemo Oracle login
 )
*/

%macro createLoginObject(
   Person_Name=     /* REQUIRED: metadata name for Person object                       */
  ,Authdomain=      /* REQUIRED: metadata name for the Authdomain for the Login object */
  ,Login_userid=    /* OPTIONAL: userid attribute for the Login object                 */
  ,Login_password=  /* OPTIONAL: password attribute for the Login object               */
  ,Login_Name=      /* OPTIONAL: metadata name for the Login object                    */
 );

  %let _rc=0;
  %* Check required parameters;
  %if "&person_name" = "" %then %do;
    %put ERROR: required parameter Person_Name= not specified;
    %let _rc=1;
  %end;

  %if "&authdomain" = "" %then %do;
    %put ERROR: required parameter Authdomain= not specified;
    %let _rc=1;
  %end;

  %if &_rc=1 %then %abort cancel &_rc;  %* exit if required parameters are not provided;

  %* generate a name for the Login object if one is not provided;
  %if "&login_name" = "" %then %let login_name = %str(&sysuserid login object for &authdomain);

  data _null_;
    /**** Initialize Variables ****/
    length person_uri domain_uri login_uri $ 50 domain_obj person_obj $ 100;
    call missing (of _character_);


    /* Find the URI for the named Person */
    person_obj="omsobj:Person?@Name='"||trim("&person_name")||"'";
    rc=metadata_getnobj(person_obj,1,person_uri);
    if rc ^= 1 then do;
	  put 'ERROR: Could not locate Person object for &person_name';
	  put person_obj= rc= person_uri=;
	end;

	/* Find the URI for the named Authentication Domain */
	if rc = 1 then do;
      domain_obj="omsobj:AuthenticationDomain?@Name='"||trim("&authdomain")||"'";
      rc=metadata_getnobj(domain_obj,1,domain_uri);
      if rc ^= 1 then do;
	    put 'ERROR: Could not locate authentication domain object for &authdomain';
	    put domain_obj= rc= domain_uri=;
      end;
    end;

	/* if we have a Person and an AuthDomain, then create the Login object */
	if rc = 1 then do;
      rc=metadata_newobj("Login",login_uri,"&login_name");
    
      /* Add some required attributes */
      if rc = 0 then rc=metadata_setattr(login_uri,"PublicType","Login");
      if rc = 0 then rc=metadata_setattr(login_uri,"UsageVersion","1000000.0");
      if rc = 0 then rc=metadata_setattr(login_uri,"IsHidden","0");
  
      /* Add some optional attributes */
	  %if "&login_userid" ^= "" %then %do;
        if rc = 0 and "&login_userid" ^= "" then rc=metadata_setattr(login_uri,"Userid","&login_userid");
	  %end;
	  %if "&login_password" ^= "" %then %do;
        if rc = 0 and "&login_password" ^= "" then rc=metadata_setattr(login_uri,"Password","&login_password");
	  %end;
    
      /* Add the AssociatedIdentity association to the Login object*/
      if rc = 0 then rc=metadata_setassn(login_uri,"AssociatedIdentity","APPEND",person_uri);
    
      /* Add the Domain association to the Authdomain */
      if rc = 0 then rc=metadata_setassn(login_uri,"Domain","APPEND",domain_uri);

	  if rc ^= 0 then do;
        put 'ERROR: Could not create Login object or set attributes';
		put login_uri= person_uri= domain_uri=;
	  end;
	end; /* create Login object */
  run;
%mend createLoginObject;

