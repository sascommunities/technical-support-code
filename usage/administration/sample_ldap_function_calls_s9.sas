/******************************************************************************/
/* This program demonstrates the usage of LDAPS function calls like those     */
/* used by the user bulkload programs to load users into Metadata.            */
/* Date: 24DEC2019                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define LDAP connection information */
%let LDServer="ldap.example.com";
%let LDPort=389;
%let LDBindUser="CN=LDAP Bind User,OU=Users,DC=example,DC=com";
%let LDBindPW="Password";
%let LDUserBaseDN="OU=Users,DC=example,DC=com";
%let LDGrpBaseDN="OU=Groups,DC=example,DC=com";
%let UserFilter="(objectclass=person)";
%let GrpFilter="(objectclass=group)";

/* End edit */

data _null_;

  /* Set DATA step variables from Macro variables. */
  server=&LDServer;
  port=&LDPort;
  ubase=&LDUserBaseDN;
  gbase=&LDGrpBaseDN;
  bindDN=&LDBindUser;
  Pw=&LDBindPW;
  ufilter=&UserFilter;
  gfilter=&GrpFilter;
  option="TLS_MODE_ON";

  /* Initialize other variables. */
  length entryName attribName value $ 255;
  call missing (entryName,attribName,value);

  /* Here you can limit the attributes returned. */
  attrs=" ";

  /* *******User demo******* */

  /* Establish a connection to LDAP and output the results. */
  if missing(option) then call LDAPS_OPEN(lHandle,server,port,ubase,bindDN,Pw,rc);
  else call LDAPS_OPEN(lHandle,server,port,ubase,bindDN,Pw,rc,option);

  put "LDAPS_Open: " rc=;
  msg = sysmsg();
  put msg=;

  /* Search LDAP using the filter provided and return the number of entries found. */
  call LDAPS_SEARCH(lHandle,sHandle,ufilter,attrs,numEntries,rc);

  put "LDAPS_Search: " rc= numEntries=;

  do i=1 to 1 /*numEntries*/ ;

    /* For the first entry (or all if replace 1 with numEntries above) pull the name and the number of attributes returned. */
    call LDAPS_ENTRY(sHandle,i,entryName,numAttrs,rc);
    put "LDAPS_Entry: " i= rc= entryName= numAttrs=;

    /* For each attribute, pull the name and number of values. */
    do j=1 to numAttrs;
      call LDAPS_ATTRNAME(sHandle,i,j,attribName,numValues,rc);
      put "LDAPS_AttrName: " j= rc= numValues= attribName=;

      /* For each value defined for the attribute, pull the value. */
      do k=1 to numValues;
        call LDAPS_ATTRVALUE(sHandle,i,j,k,value,rc);
        put "LDAPS_AttrValue: " k= rc= value=;
      end;
    end;
  end;

  /* Close the connection to LDAP. */
  call LDAPS_CLOSE(lHandle,rc);

  put "LDAPS_Close: " rc=;

  /* *******Group demo******* */

  /* Establish a connection to LDAP and output the results. */
  if missing(option) then call LDAPS_OPEN(lHandle,server,port,gbase,bindDN,Pw,rc);
  else call LDAPS_OPEN(lHandle,server,port,gbase,bindDN,Pw,rc,option);
  put "LDAPS_Open: " rc=;
  msg = sysmsg();
  put msg=;

  /* Search LDAP using the filter provided and return the number of entries found. */
  call LDAPS_SEARCH(lHandle,sHandle,gfilter,attrs,numEntries,rc);

  put "LDAPS_Search: " rc= numEntries=;

  do i=1 to 1 /*numEntries*/ ;

    /* For the first entry (or all if replace 1 with numEntries above) pull the name and the number of attributes returned. */
    call LDAPS_ENTRY(sHandle,i,entryName,numAttrs,rc);
    put "LDAPS_Entry: " i= rc= entryName= numAttrs=;

    /* For each attribute, pull the name and number of values. */
    do j=1 to numAttrs;
      call LDAPS_ATTRNAME(sHandle,i,j,attribName,numValues,rc);
      put "LDAPS_AttrName: " j= rc= numValues= attribName=;

      /* For each value defined for the attribute, pull the value. */
      do k=1 to numValues;
        call LDAPS_ATTRVALUE(sHandle,i,j,k,value,rc);
        put "LDAPS_AttrValue: " k= rc= value=;
      end;
    end;
  end;

  /* Close the connection to LDAP. */
  call LDAPS_CLOSE(lHandle,rc);

  put "LDAPS_Close: " rc=;

run;