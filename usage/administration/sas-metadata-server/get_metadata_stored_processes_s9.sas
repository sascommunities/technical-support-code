/******************************************************************************/
/* This program will extract a list of all stored processes defined in        */
/* Metadata and their Metadata path.                                          */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 07FEB2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define credentials to Metadata Server connection. */

options metaserver="<hostname>"
		metaport=8561
		metarepository=Foundation
		metaprotocol=bridge
		metauser="sasadm@saspw"
		metapass="<password>";

data work.stp_paths;

/* Define and initialize variables. */

length 	type $ 13 
		id $ 17 
		stp_uri $ 38 	
		tree_uri  
		partree_uri $ 29 
		path $ 200 
		folder_name 
		stp_name $ 100 
		stp_create 
		stp_update $ 18
		;

call missing(type,id,stp_uri,tree_uri,partree_uri,path,folder_name,stp_name,stp_create,stp_update);

obj="omsobj:ClassifierMap?@PublicType='StoredProcess'";

/* Check for existence of stored processes. */
stp_count=metadata_resolve(obj,type,id);

if stp_count > 0 then do n=1 to stp_count;

/* Get attributes of each stored process. */
	rc=metadata_getnobj(obj,n,stp_uri);
	rc=metadata_getattr(stp_uri,"Name",stp_name);
	rc=metadata_getattr(stp_uri,"MetadataCreated",stp_create);
	rc=metadata_getattr(stp_uri,"MetadataUpdated",stp_update);
	stp_create_num=input(stp_create,DATETIME18.);
	stp_update_num=input(stp_update,DATETIME18.);
	rc=metadata_getnasn(stp_uri,"Trees",1,tree_uri);
	rc=metadata_getattr(tree_uri,"Name",folder_name);
	path=catx("\",folder_name);
	parent_rc=metadata_getnasn(tree_uri,"ParentTree",1,partree_uri);
		/* Build path. */
		do while (parent_rc > 0);
		rc=metadata_getattr(partree_uri,"Name",folder_name);
		path=catx("\",folder_name,path);
		parent_rc=metadata_getnasn(partree_uri,"ParentTree",1,partree_uri);		
		end;
		output;
end;
else put "No stored processes defined in Metadata.";
format stp_create_num stp_update_num datetime18.;
run;

PROC SQL;
	CREATE TABLE work.stp_paths_sorted AS
	SELECT path,stp_name,stp_create_num,stp_update_num FROM work.stp_paths ORDER BY stp_update_num ,path;
quit;
