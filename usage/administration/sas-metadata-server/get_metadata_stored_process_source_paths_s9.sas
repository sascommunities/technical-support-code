/******************************************************************************/
/* This program will extract from Metadata the source path for each stored    */
/* process defined that has external file source code.                        */
/* Date: 07FEB2024                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Edit with connection information for the Metadata Server. */

options metaserver="meta.demo.sas.com"
		metaport=8561
		metauser="sasadm@saspw"
		metapass="password"
		metarepository=Foundation
		metaprotocol=bridge;

/* End Edit. */

data source;

	keep stp_name source; /* Retain only the stored process name and it's source code full path. */

/* Initialize variables. */

	length type id stp_uri stp_name file_uri file_name dir_uri path $ 50; 
	call missing (of _character_);

	obj="omsobj:ClassifierMap?ClassifierMap[@PublicType='StoredProcess'][SourceCode/File]"; /* Search critera for Stored Processes that have an external file source. */

	stp_count=metadata_resolve(obj,type,id); /* Count all stored processes that meet our criteria. Only run loop if at least one exists. */

	if stp_count > 0 then do i=1 to stp_count; /* Loop: For each stp found, get attributes and associations. */
		rc=metadata_getnobj(obj,i,stp_uri);
		rc=metadata_getattr(stp_uri,"Name",stp_name); /* Get stp name. */
		rc=metadata_getnasn(stp_uri,"SourceCode",1,file_uri); /* Get file Metadata object id.  */
		rc=metadata_getattr(file_uri,"FileName",file_name); /* Get file name. */
		rc=metadata_getnasn(file_uri,"Directories",1,dir_uri); /* Get directory Metadata object id.  */
		rc=metadata_getattr(dir_uri,"DirectoryName",path); /* Get path to directory. */
		source=catx('/',path,file_name); /* combine directory path and file name to create full path to file.*/
		output;
	end; /* End loop. */
	else put "WARN: No Stored Processes with external source code files found in Metadata."; /* If no jobs are found, write a message to the log. */
run;