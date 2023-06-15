/******************************************************************************/
/* This program searches metadata for any tables being used for dynamic       */
/* prompts for stored processes, or stored processes that make use of dynamic */
/* prompts.                                                                   */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 01JUL2020                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define connection to Metadata. */

options metaserver='meta.demo.sas.com'
metaport=8561
metaprotocol='bridge'
metauser='sasadm@saspw'
metapass='password'
metarepository='Foundation'
metaconnect='NONE'
;

/* End edit. */


/* This data step searches for any "PhysicalTable" metadata object with an association */
/* to a prompt or prompt group, suggesting it is being used by dynamic prompting. */

data _null_;
/* Initialize variables. */
	length type id $ 50 tab_uri tab_name lib_uri lib_name $ 255;
	call missing(of _character_);
	/* Define a variable "obj" that contains the query for the tables. */
	obj="omsobj:PhysicalTable?PhysicalTable[SourceClassifierMaps/ClassifierMap/AssociatedPrompt/Prompt] or [SourceClassifierMaps/ClassifierMap/AssociatedPrompt/PromptGroup]";
	table_count=metadata_resolve(obj,type,id); /* Count the tables found. */
	put "NOTE: Found " table_count "tables used by dynamic prompts.";
	/* For each table found, pull the name and the name of the library it is associated with. */
	if table_count > 0 then do i=1 to table_count;
		rc=metadata_getnobj(obj,i,tab_uri);
		rc=metadata_getattr(tab_uri,"Name",tab_name);
		rc=metadata_getnasn(tab_uri,"TablePackage",1,lib_uri);
		rc=metadata_getattr(lib_uri,"Name",lib_name);
		put lib_name= tab_name=; /* Write the library and table name to the log. */
	end;
run;


/* This data step searches for stored processes that have an associated prompt or */
/* prompt group that has a table association, suggesting a dynamic prompt.*/
data custom_report ;
/* Initialize variables. */
	length type id $ 50 stp_uri stp_name prmpt_uri cm_uri tab_uri tab_name lib_uri lib_name fldr_uri fldr_name partree_uri prmpt_name tabtree_uri tabtree_name partabtree_uri $ 255;
	call missing(of _character_);
	/* Define a variable "obj" that contains the query. */
	obj="omsobj:ClassifierMap?ClassifierMap[Prompts/Prompt/ValueSource/ClassifierMap/ClassifierSources/PhysicalTable] or [Prompts/PromptGroup/ValueSource/ClassifierMap/ClassifierSources/PhysicalTable]";
	stp_count=metadata_resolve(obj,type,id);
	/* Count the number of stored processes found. */
	put "NOTE: Found " stp_count "stored processes that use dynamic prompts.";

	/* For each one, get its name, associated prompts and their associated tables and libraries. */
	if stp_count > 0 then do i = 1 to stp_count;
		rc=metadata_getnobj(obj,i,stp_uri);
		rc=metadata_getattr(stp_uri,"Name",stp_name);
		rc=metadata_getnasn(stp_uri,"Trees",1,fldr_uri);
		rc=metadata_getattr(fldr_uri,"Name",fldr_name);

		path=catx("\",fldr_name);
		parent_rc=metadata_getnasn(fldr_uri,"ParentTree",1,partree_uri);
		/* Build path. */
		do while (parent_rc > 0);
		rc=metadata_getattr(partree_uri,"Name",fldr_name);
		path=catx("\",fldr_name,path);
		parent_rc=metadata_getnasn(partree_uri,"ParentTree",1,partree_uri);		
		end;

		prmpt_cnt=metadata_getnasn(stp_uri,"Prompts",1,prmpt_uri);
		if prmpt_cnt > 0 then do j = 1 to prmpt_cnt;
			rc=metadata_getnasn(stp_uri,"Prompts",j,prmpt_uri);
			rc=metadata_getattr(prmpt_uri,"Name",prmpt_name);
			cm_cnt=metadata_getnasn(prmpt_uri,"ValueSource",1,cm_uri);
			if cm_cnt > 0 then do k = 1 to cm_cnt;
				rc=metadata_getnasn(prmpt_uri,"ValueSource",k,cm_uri);
				rc=metadata_getnasn(cm_uri,"ClassifierSources",1,tab_uri);
				rc=metadata_getattr(tab_uri,"Name",tab_name);

				rc=metadata_getnasn(tab_uri,"Trees",1,tabtree_uri);
				rc=metadata_getattr(tabtree_uri,"Name",tabtree_name);
				tabpath=catx("\",tabtree_name);
				parent_rc=metadata_getnasn(tabtree_uri,"ParentTree",1,partabtree_uri);
				/* Build path. */
				do while (parent_rc > 0);
				rc=metadata_getattr(partabtree_uri,"Name",tabtree_name);
				tabpath=catx("\",tabtree_name,tabpath);
				parent_rc=metadata_getnasn(partabtree_uri,"ParentTree",1,partabtree_uri);		
				end;

				rc=metadata_getnasn(tab_uri,"TablePackage",1,lib_uri);
				rc=metadata_getattr(lib_uri,"Name",lib_name);
				output;
				put path= stp_name= prmpt_name= lib_name= tabpath= tab_name=; /* Write the stored process name, library name and table name to the log. */
			end;
		end;
	end;
run;

proc print data=custom_report;
	var path stp_name prmpt_name lib_name tabpath tab_name;
run;
