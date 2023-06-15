/******************************************************************************/
/* This program will output the extended attributes for a given LASR table.   */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 16MAY2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Provide the name of the library you would */
/* like to extract the Extended Attributes from. */
%let libname='Visual Analytics LASR';

/* Modify the options to provide the connection */
/* information and credentials for the Metadata Server. */
options
  metaserver="meta.demo.sas.com"
  metaport=8561
  metauser="sasadm@saspw"
  metapass="password"
  metarepository=Foundation
  metaprotocol=bridge;

data extend;
/* Declare and initialize variables. */

  length type id lib_uri ext_uri ext_name $ 50 ext_val $ 256;
  call missing(of _CHARACTER_);

/* Defined the query to locate the library. */

  obj="omsobj:SASLibrary?@Name=&libname";

/* Test for the library, end if not found. */

  libcount=metadata_resolve(obj,type,id);
  if libcount > 0 then do n=1 to libcount;

    /* For each library found that matches the query, */
    /* count the number of extended attributes. */

    rc=metadata_getnobj(obj,n,lib_uri);
    ext_count=metadata_getnasn(lib_uri,"Extensions",1,ext_uri);

    /* End if no extended attributes are found. */

    if ext_count > 0 then do m=1 to ext_count;

    /* If attributes found, extract the name and */
    /* value of each one, and output to a dataset. */

      rc=metadata_getnasn(lib_uri,"Extensions",m,ext_uri);
      rc=metadata_getattr(ext_uri,"Name",ext_name);
      rc=metadata_getattr(ext_uri,"Value",ext_val);
      output;
    end; else put "NOTE: No Extended Attributes found for library &libname";
  end;
  else put "NOTE: No library &libname found.";

  /* Only keep the extension details. */

  keep ext_name ext_val;
run;