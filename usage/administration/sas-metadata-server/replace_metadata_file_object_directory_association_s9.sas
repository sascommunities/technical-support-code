/******************************************************************************/
/* This program accepts an old and new Directory object URI. For each file    */
/* object found with the old URI, it replaces this association with the new   */
/* URI. This program was written to address an issue after a migration where  */
/* deployed jobs could not be scheduled because the path had changed.         */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 24JUL2018                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Set connection information for the Metadata Server. */

options
  metaserver='meta.demo.sas.com'
  metaport=8561
  metauser='sasadm@saspw'
  metapass='password'
  metarepository='Foundation';

/* End connection stanza. */

data _null_;
  /* Set the old and new IDs. */
  %let olddir = 'A5STBUB8.B6000002';
  %let newdir = 'A5STBUB8.B6000002';
  /* End edit. */

/* Initialze variables. */

  length type id old_uri new_uri file_uri $ 50;
  call missing(of _character_);

/* Confirm the directories exist, and stop if they do not. */

  rc=metadata_resolve("omsobj:Directory?@Id = &olddir",type,id);

if rc <= 0 then do;
  put "ERROR: Supplied old directory object ID not found in Metadata";
  stop;
end;

  rc=metadata_resolve("omsobj:Directory?@Id = &newdir",type,id);

if rc <= 0 then do;
  put "ERROR: Supplied new directory object ID not found in Metadata";
  stop;
end;

/* set their URI as a variable. */

rc=metadata_getnobj("omsobj:Directory?@Id = &olddir",1,old_uri);
rc=metadata_getnobj("omsobj:Directory?@Id = &newdir",1,new_uri);

/* Count the number of files associated with the old directory. */

file_count=metadata_getnasn(old_uri,"Files",1,file_uri);

/* For each one, associate with the new directory. */

if file_count > 0 then do i=1 to file_count;
  file_count=metadata_getnasn(old_uri,"Files",i,file_uri);
  rc=metadata_setassn(file_uri,"Directories","REPLACE",new_uri);
  put _all_;
end;

run;