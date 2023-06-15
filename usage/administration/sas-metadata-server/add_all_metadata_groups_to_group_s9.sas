/******************************************************************************/
/* This program will add all groups defined in Metadata to the defined group. */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 22AUG2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define Metadata connection information. */
options
  metaserver="meta.demo.sas.com"
  metaport=8561
  metauser="sasadm@saspw"
  metapass="password"
  metarepository=Foundation
  metaprotocol=bridge;

%let addgroup='Red Test'; /* Group to add all other groups to. */

data _null_;

/* Initialize variables. */

length type id addgroup_uri group_uri group_name $ 50;
call missing (of _character_);

/* Set queries for all groups and for specific group. */

group_obj="omsobj:IdentityGroup?@Name=&addgroup";
allgrp_obj="omsobj:IdentityGroup?@PublicType='UserGroup'";

/* Get URI for the group name defined in the 'addgroup' macro variable above. */
rc=metadata_getnobj(group_obj,1,addgroup_uri);

/* Count all groups. */

group_count=metadata_resolve(allgrp_obj,type,id);

/* If there are groups, do this for each group... */

if group_count > 0 then do n=1 to group_count;

/* Get the URI of the group. */

  rc=metadata_getnobj(allgrp_obj,n,group_uri);

/* Get the name of the group. */

  rc=metadata_getattr(group_uri,"Name",group_name);

  /* If the group name is that of the addgroup, do nothing. */

  if group_name = &addgroup then;
  else do; /* If not... */
    put "Adding " group_name;
    /* Add it to the membership. */
    rc = metadata_setassn(addgroup_uri,"MemberIdentities","APPEND",group_uri);
    end;
end;
run;