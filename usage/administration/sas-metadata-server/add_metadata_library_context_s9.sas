/******************************************************************************/
/* This program will add a new application server context assignment to       */
/* libraries that match the query defined in the libobj variable.             */
/* Note: The program assumes none of the matching libraries already have the  */
/* context assigned.                                                          */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 16JUN2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Set connection options for the Metadata server. */

options
  metaserver="meta.demo.sas.com"
  metaport=8561
  metauser="sasadm@saspw"
  metapass="password"
  metarepository=Foundation
  metaprotocol=Bridge;

/* End connection settings. */

data _null_;

/* Initialize variables. */

  length type id app_uri lib_uri $ 50;
  call missing(of _character_);

/* Define query for the Application Server Context */
/* to add to the libraries and search for it. */

  appobj="omsobj:ServerContext?@Name='SASSTP'";
  app_count=metadata_resolve(appobj,type,id);

/* If no context matches this query, stop the program with an error. */

  if app_count <= 0 then do;
    put "ERROR: No application server context found matching query " appobj;
    stop;
    end;
  else do;

/* Extract the URI of the context if it exists. */

    rc=metadata_getnobj(appobj,1,app_uri);

/* Define the query for the libraries to be updated and search for them. */

    libobj="omsobj:SASLibrary?@Id contains '.'";
    lib_count=metadata_resolve(libobj,type,id);

/* If no libraries match the query, stop the program with an error. */
    if lib_count <= 0 then do;
                put "ERROR: No libraries found matching query " libobj;
                stop;
                end;

/* If libraries are found, for each one append */
/* the context to its list of associated contexts. */

    else do n=1 to lib_count;
      rc=metadata_getnobj(libobj,1,lib_uri);
      rc=metadata_setassn(lib_uri,"DeployedComponents","Append",app_uri);
    end;
  end;
run;
