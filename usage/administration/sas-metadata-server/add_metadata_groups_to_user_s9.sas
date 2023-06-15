/******************************************************************************/
/* This program will add a list of groups to a supplied user.                 */
/* Date: 09OCT2020                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Provide the name (not display name) of the user you wish to add to the groups. */
%let username=sasadm;

/* Create a list of groups */
data groups;
    length name $ 255;
    call missing (of _character_);
    input;
    name=_infile_;
    datalines;
group1
group2
groupn
    ;;
run;

/* Add each one to the supplied user */
data _null_;
    set groups;
    user_obj="omsobj:Person?@Name='&username'";
	group_obj="omsobj:IdentityGroup?@Name='"||name||"'";
	rc=metadata_setassn(user_obj,"IdentityGroups","APPEND",group_obj);
run;