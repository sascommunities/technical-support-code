/******************************************************************************/
/* This program searches for Enterprise Miner projects that contain a given   */
/* path, and replaces that path with a new path in the log and optionally     */
/* in Metadata as well. This was written to address a customer request to     */
/* replace a shared drive with a UNC path (replace D:\ with \\server\share\)  */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 15JUN2021                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Specify connection information for the Metadata Server. */
options
  metaserver="meta.demo.sas.com"
  metaport=8561
  metauser="sasadm@saspw"
  metapass="password";

/* Define the path you want to replace, and what you want to replace it with. */
%let oldpath=D:\;
%let newpath=\\server\share\;

/* Start a data step */
data _null_;

/* Initialize variables */
/* If your full path is more than 255 characters, */
/* you may need to increase the length here. */

length type $ 15 id $ 17 uri $ 40 olddir newdir $ 255;

call missing (of _character_);

/* Define a metadata query that locates Enterprise Miner */
/* Projects whose path contains the path we are trying to replace. */
obj="omsobj:AnalyticContext?@PublicType='MiningProject'
  and @DirectoryName contains '&oldpath'";

/* Count how many objects exist that match that query. */
count=metadata_resolve(obj,type,id);

/* Write that information to the log.*/
put "NOTE: Found " count "mining projects with &oldpath in their path.";
put;

/* If any are found, loop through each one and extract the path. */
if count > 0 then do i = 1 to count;
  rc=metadata_getnobj(obj,i,uri);
  rc=metadata_getattr(uri,"DirectoryName",olddir);
  /* Write the old directory to the log. */
  put "NOTE: Found matching project path " olddir;
  /* Use the tranwrd function to replace the old path with the new */
  /* in a new variable. */
  newdir=tranwrd(olddir,"&oldpath","&newpath");
  put "NOTE: Replacing the path results in " newdir;
  put;
  /*Uncomment the section below to write the new path value.*/
  /*
  rc=metadata_setattr(uri,"DirectoryName",newdir);
  put "NOTE: METADATA_SETATTR return code " rc=;
  if rc ne 0 then do;
    put "ERROR: METADATA_SETATTR did not return 0.";
    stop;
  end;
  */
end;

/* If no projects are found, return a warning. */
else put "WARNING: No projects found with &oldpath in their path.";
run;