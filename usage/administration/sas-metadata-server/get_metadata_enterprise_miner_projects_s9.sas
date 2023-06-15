/******************************************************************************/
/* This program will get a list of all Enterprise Miner projects in Metadata. */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 30NOV2016                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* This section should be edited with the connection information specific to your Metadata server. */

options
	metaserver="hostname"
	metaport=8561
	metauser="sasadm@saspw"
	metapass="password"
	metarepository=Foundation
	metaprotocol=BRIDGE;

/* End edit section */

data work.minerprojects; 
	
	length /* define variable lengths */
		Project_uri $ 40
		Project_id $ 17
		Project_name $ 255
		Project_physicalpath $ 255
		Tree_uri $ 29
		treePath $ 255
		parentTree_uri $ 29
		parentTreePath $ 255
		metadataPath $ 255
		owner_uri $ 41
		owner_name $ 50
		obj $ 50
		type $ 15
		id $ 17
		project_count 8
		n 8
		rc 3
		parent_rc 3
		modifiedDate $ 20
		modifiedDateNum 8;

		format modifiedDateNum DATETIME7.;

/* define kept column labels */

	label Project_name="Project Name" Project_physicalpath="Physical Path" metadataPath="Metadata Path" owner_name="Owner" modifiedDateNum="Last Modified Date";

/* define kept columns */

	keep Project_name Project_physicalpath metadataPath owner_name modifiedDateNum;

/* define the Object Type shorthand variable to locate Enterprise Miner projects */

	obj="omsobj:AnalyticContext?@PublicType='MiningProject'";

/* Initialize the variables */

	call missing(modifiedDateNum,modifiedDate,Project_uri,Project_id,Project_name,Project_physicalpath,Tree_uri,treePath,parentTree_uri,parentTree_uri,parentTreePath,metadataPath,owner_uri,owner_name,type,id);

/* Determine if any Enterprise Miner projects exist in Metadata */

	project_count=metadata_resolve(obj,type,id);

/* If so, pull data for each project. */

	if project_count > 0 then do n = 1 to project_count;
		rc=metadata_getnobj(obj,n,Project_uri);
		rc=metadata_getattr(Project_uri,"Id",Project_id);
		rc=metadata_getattr(Project_uri,"Name",Project_name);
		rc=metadata_getattr(Project_uri,"DirectoryName",Project_physicalpath);
		rc=metadata_getnasn(Project_uri,"Trees",1,Tree_uri);
		rc=metadata_getattr(Tree_uri,"Name",treePath);
		metadataPath=treePath;
		parent_rc=metadata_getnasn(Tree_uri,"ParentTree",1,parentTree_uri); /* Determine if the metadata folder is top-level */
		if parent_rc > 0 then do while (parent_rc > 0); /* If not, this loop assembles the metadata path, as these are nested "Tree" objects. */
			rc=metadata_getattr(parentTree_uri,"Name",parentTreePath);
			metadataPath=cats(parentTreePath,"\",metadataPath);
			parent_rc=metadata_getnasn(parentTree_uri,"ParentTree",1,parentTree_uri);
		end;
		metadataPath=cats("\",metadataPath);
		rc=metadata_getnasn(Project_uri,"ResponsibleParties",1,owner_uri);
		rc=metadata_getattr(owner_uri,"Name",owner_name);
		rc=metadata_getattr(Project_uri,"MetadataUpdated",modifiedDate);
		modifiedDateNum=input(modifiedDate,DATETIME.);
		output;
	end;
	else put "No Miner Projects Found";
run;