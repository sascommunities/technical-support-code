/******************************************************************************/
/* This program will extract from Metadata the source path for each job       */
/* defined.                                                                   */
/* Date: 09JUL2018                                                            */
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

	keep job_name source; /* Retain only the job name and it's source code full path. */

/* Initialize variables. */

	length type id job_uri job_name file_uri file_name dir_uri path $ 50; 
	call missing (of _character_);

	obj="omsobj:Job?@Id contains '.'"; /* Search critera for Jobs. */

	job_count=metadata_resolve(obj,type,id); /* Count all jobs. Only run loop if jobs exist. */

	if job_count > 0 then do i=1 to job_count; /* Loop: For each job found, get attributes and associations. */
		rc=metadata_getnobj(obj,i,job_uri);
		rc=metadata_getattr(job_uri,"Name",job_name); /* Get job name. */
		rc=metadata_getnasn(job_uri,"SourceCode",1,file_uri); /* Get file Metadata object id.  */
		rc=metadata_getattr(file_uri,"Name",file_name); /* Get file name. */
		rc=metadata_getnasn(file_uri,"Directories",1,dir_uri); /* Get directory Metadata object id.  */
		rc=metadata_getattr(dir_uri,"DirectoryName",path); /* Get path to directory. */
		source=catx('/',path,file_name); /* combine directory path and file name to create full path to file.*/
		output;
	end; /* End loop. */
	else put "WARN: No jobs found in Metadata."; /* If no jobs are found, write a message to the log. */
run;