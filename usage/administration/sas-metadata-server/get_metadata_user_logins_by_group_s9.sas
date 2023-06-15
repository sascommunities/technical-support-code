/******************************************************************************/
/* This program will list the first user ID for each member of a given group. */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 09DEC2019                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Modify this section with your Metadata connection information. */

options metaserver="meta.demo.sas.com"
		metaport=8561
		metauser="sasadm@saspw"
		metapass="Password"
		metarepository=Foundation
		metaprotocol=Bridge;
/* Provide a group name you would like to query. */
%let groupname=SAS Administrators;
/*END EDIT. */

data usertab;
length type id group_uri group_name per_uri per_name log_uri user_id ad_uri ad_name $ 256;
call missing(type,id,group_uri,group_name,per_uri,per_name,log_uri,user_id,ad_uri,ad_name);
obj="omsobj:IdentityGroup?@DisplayName='&groupname'";
groupCount=metadata_resolve(obj,type,id);
put groupCount=;
if groupCount = 0 then do;
	put "ERROR: No groups named &groupname defined in the repository.";
	stop;
end;
if groupCount > 0 then do n=1 to groupCount;
	rc=metadata_getnobj(obj,n,group_uri);
	rc=metadata_getattr(group_uri,"DisplayName",group_name);
	put group_name=;
	memCount=metadata_getnasn(group_uri,"MemberIdentities",1,per_uri);
	if memCount > 0 then do m=1 to memCount;
		rc=metadata_getnasn(group_uri,"MemberIdentities",m,per_uri);
		rc=metadata_getattr(per_uri,"DisplayName",per_name);
		logCount=metadata_getnasn(per_uri,"Logins",1,log_uri);
		if logCount > 0 then do o=1 to logCount;
			rc=metadata_getnasn(per_uri,"Logins",o,log_uri);
			rc=metadata_getattr(log_uri,"UserID",user_id);
			rc=metadata_getnasn(log_uri,"Domain",1,ad_uri);
			rc=metadata_getattr(ad_uri,"Name",ad_name);
			output;
			call missing(log_uri,user_id,ad_uri,ad_name,group_name,per_name);
		end;
	end; 
end; 
keep group_name per_name ad_name user_id;
run;