/******************************************************************************/
/* This program pulls inforamtion on SAS libraries and tables defined         */
/* in Metadata.                                                               */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 08FEB2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define Metadata Server connection. */
options
  metaserver="meta.demo.sas.com"
  metaport=8561
  metauser="sasadm@saspw"
  metapass="password"
  metarepository=Foundation
  metaprotocol=bridge;

data work.libinfo;

/*declare and initialize variables */
  length
    type $ 20
    lib_ref $ 8
    lib_uri lib_name app_uri app_name dir_uri tab_uri tab_name $ 50
    id lib_id $ 17
    path $ 255;
  keep lib_ref lib_name tab_name;
  call missing(of _character_);

  /* Define library search parameters. */
  obj="omsobj:SASLibrary?@Id contains '.'";

  /* Search Metadata for libraries */

  libcount=metadata_resolve(obj,type,id);
  put "INFO: Found " libcount "libraries.";

  /* for each library found, extract name and associated */
  /* properties (first associated application server, path) */
  if libcount > 0 then do n=1 to libcount;

  rc=metadata_getnobj(obj,n,lib_uri);
  rc=metadata_getattr(lib_uri,"Name",lib_name);
  rc=metadata_getattr(lib_uri,"Id",lib_id);
  rc=metadata_getattr(lib_uri,"Libref",lib_ref);
  rc=metadata_getnasn(lib_uri,"DeployedComponents",1,app_uri);
  rc=metadata_getattr(app_uri,"Name",app_name);
  rc=metadata_getnasn(lib_uri,"UsingPackages",1,dir_uri);
  rc=metadata_getattr(dir_uri,"DirectoryName",path);

  /* Define a query to search for any tables */
  /* associated with the library in Metadata. */

  tabobj="omsobj:PhysicalTable?PhysicalTable[TablePackage/SASLibrary[@Id='"||lib_id||"']] or [TablePackage/DatabaseSchema/UsedByPackages/SASLibrary[@Id='"||lib_id||"']]";

  /* Count how many associations exist. */

  tabcount=metadata_resolve(tabobj,type,id);

  /* If there are any, pull the name of each one and write out the data set. */

  if tabcount > 0 then do t=1 to tabcount;
    rc=metadata_getnobj(tabobj,t,tab_uri);
    rc=metadata_getattr(tab_uri,"Name",tab_name);
    output; /* Push results to table  */
  end;
  call missing (path); /* clear path variable. */
  end;
  else put "INFO: No libraries to resolve.";
run;