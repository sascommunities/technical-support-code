/******************************************************************************/
/* This program will list all metadata groups and their members.              */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 29JUN2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Edit Metadata connection information. */

options metaserver="meta.demo.sas.com"
		metaport=8561
		metauser="sasadm@saspw"
		metapass="password"
		metarepository=Foundation
		metaprotocol=bridge;
/* End edit. */

data groups;
/* Initialize variables. */
length type id group_uri group_name mgroup_uri muser_uri m_name $ 50 m_dn group_dn $ 256;
call missing(of _character_);
label group_name = "Group Name"
	  group_dn = "Group Display Name"
	  m_name = "Member Name"
      m_dn = "Member Display Name"
	  ;


/* Define initial query for groups. */
group_obj="omsobj:IdentityGroup?@PublicType='UserGroup'";

/* Test query for results. */
group_count=metadata_resolve(group_obj,type,id);
put "NOTE: Found " group_count "User Groups";
if group_count > 0 then do n=1 to group_count;

/* If groups are found, get each group's name and display name. */
	rc=metadata_getnobj(group_obj,n,group_uri);
	rc=metadata_getattr(group_uri,"Name",group_name);
	rc=metadata_getattr(group_uri,"DisplayName",group_dn);
	

/* Test for presence of members associated with the group. */
	muser_count=metadata_getnasn(group_uri,"MemberIdentities",1,muser_uri);
	if muser_count > 0 then do o=1 to muser_count;

/* If found, extract each associated user's name and display name. */
		rc=metadata_getnasn(group_uri,"MemberIdentities",o,muser_uri);
		rc=metadata_getattr(muser_uri,"Name",m_name);
		rc=metadata_getattr(muser_uri,"DisplayName",m_dn);
		output;
		call missing (m_name,m_dn);
	end;
	else do;
		put "NOTE: No members of group " group_name group_dn;
		output;
		end;
end;
else put "ERROR: No groups found";
keep group_name group_dn m_name m_dn ;
run;

proc report data=groups;
	column group_name group_dn m_name m_dn ;
run;
