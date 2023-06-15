/******************************************************************************/
/* This program will get from metadata all file references and output them to */
/* a SAS dataset called directories.                                          */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 09DEC2019                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define metadata connection information. */
options metaserver='meta.demo.sas.com'
metaport=8561
metaprotocol='bridge'
metauser='sasadm@saspw'
metapass='password'
metarepository='Foundation'
metaconnect='NONE'
;
/* End edit. */

/* Create a data set, "directories" */
data directories;

/* Initialize variables. */
        length type id dir_uri file_uri $ 50 path file_name fqn $ 255;
        call missing(of _character_);
        keep fqn;

/* Define a query to find all directory objects that have an associated file object. */
        obj="omsobj:Directory?Directory[Files/File[@Id contains '.']";

        /* Count the objects that match this query. */
        dir_count=metadata_resolve(obj,type,id);

        /* Proceed if any directories are found. */
        if dir_count > 0 then do i=1 to dir_count;

                /* Get the metadata URI for the nth directory object found. */
                rc=metadata_getnobj(obj,i,dir_uri);

                /* Use the URI to get the directory path. */
                rc=metadata_getattr(dir_uri,"DirectoryName",path);

                /* Find the files associated with the path. */
                file_count=metadata_getnasn(dir_uri,"Files",1,file_uri);
                if file_count > 0 then do j=1 to file_count;
                        /* For each file found, get it's URI and name. */
                        rc=metadata_getnasn(dir_uri,"Files",j,file_uri);
                        rc=metadata_getattr(file_uri,"FileName",file_name);
                        /* Output a combination of the path and file to the data set. */
                        fqn=catx("/",path,file_name);
                        output;
                end;
        end;
                /* Define a search query to find any "SASFileRef" object types. */
		obj2="omsobj:SASFileRef?@Id contains '.'";

		fileref_count=metadata_resolve(obj2,type,id);

		if fileref_count > 0 then do i = 1 to fileref_count;
                        /* If any are found, get their name, which is a full path, and output it to the data set as well. */
			rc=metadata_getnobj(obj2,i,file_uri);
			rc=metadata_getattr(file_uri,"Name",fqn);
			output;

		end;

run;
