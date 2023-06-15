/******************************************************************************/
/* This program will extract members from a Metadata group and add them to    */
/* another existing Metadata group.                                           */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 29NOV2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Edit Metadata connection information. */

options metaserver="meta.demo.sas.com"
		metaport=8561
		metauser="sasadm@saspw"
		metapass="password"
		metaprotocol=bridge
		metarepository=Foundation;

/* Specify the source and destination group names. */

%let source_group_name='source group';
%let dest_group_name='destination group';

/* End user edit. */

data _null_;

/* Initialize variables. */

length type1 type2 id1 id2 src_uri dest_uri mem_uri mem_name $ 50;
call missing (of _character_);

/* Define query. */

src_obj="omsobj:IdentityGroup?@Name=&source_group_name";
dest_obj="omsobj:IdentityGroup?@Name=&dest_group_name";

/* Test for the existence of the source group. */

rc1=metadata_resolve(src_obj,type1,id1);
src_uri=cats(type1,'\',id1);
if rc1 < 1 then do; /* If unable to locate, notify and stop.  */
	put "ERROR: Source group &source_group_name not found in Metadata.";
	stop;
end;

/* Test for the existence of the destination group. */

rc2=metadata_resolve(dest_obj,type2,id2);
dest_uri=cats(type2,'\',id2);

if rc2 < 1 then do; /* If unable to locate, notify and stop.  */
	put "ERROR: Destination group &dest_group_name not found in Metadata.";
	stop;
end;

/* Count the number of members in the source group. */

mem_count=metadata_getnasn(src_uri,"MemberIdentities",1,mem_uri);
put "NOTE: Source group &source_group_name has " mem_count "members.";

/* For each member in the source group, add the member to the destination group. */

do n=1 to mem_count;
	rc=metadata_getnasn(src_uri,"MemberIdentities",n,mem_uri);
	rc=metadata_getattr(mem_uri,"Name",mem_name);
	put "NOTE: Adding " mem_name "to destination group &dest_group_name";
	rc=metadata_setassn(dest_uri,"MemberIdentities","APPEND",mem_uri);
	put mem_uri;
end;	
run;
