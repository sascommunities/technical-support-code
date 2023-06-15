/******************************************************************************/
/* This program will extract from Metadata information on deployed jobs       */
/* without an associated flow.                                                */
/* Date: 24FEB2021                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Edit with connection information for the Metadata Server. */


options metaserver="meta.demo.sas.com"
        metaport=8561
        metauser="sasadm@saspw"
        metapass="Password"
        metarepository='Foundation'
        ;

/* End edit. */

/* Create a dataset work.djobs to hold the information. */
data djobs;
    /* Initialize variables. */
	length type id uri turi puri ruri ouri $ 50 name folder pfolder path ownerdn ownern $ 255;
	call missing ( of _character_ );
    keep name path ownern;
    label   name = "Job Name"
            path = "SAS Folder Path"
            ownern = "Owner";

    /* Define a query for JFJob objects of type "DeployedJob" that do not have a step association (no flow). */
	obj="omsobj:JFJob?JFJob[@PublicType='DeployedJob'][not(Steps/*)]";

    /* Determine how many deployed jobs meet that criteria */
	jobcount=metadata_resolve(obj,type,id);

    /* Announce how many were found. */
	put "NOTE: Found " jobcount "Deployed Jobs not assigned to a flow.";

    /* If any were found, iterate through each one to get the attributes and associations. */
	if jobcount > 0 then do i = 1 to jobcount;

        /* Get the URI for the nth job found. */
		rc=metadata_getnobj(obj,i,uri);
        /* Get the name of that job. */
		rc=metadata_getattr(uri,"Name",name);

        /* Determine ownership... */
        /* Get the URI of the first Responsible Party association, if one exists. */
		rp_rc=metadata_getnasn(uri,"ResponsibleParties",1,ruri);
		if rp_rc > 0 then do;
            /* Get the Person object associated with the responsible party. */
			rc=metadata_getnasn(ruri,"Persons",1,ouri);
            /* Get the name of the person. */
			rc=metadata_getattr(ouri,"Name",ownern);
            /* Get the display name of the person. */
			rc=metadata_getattr(ouri,"DisplayName",ownerdn);
            /* Set the display name to the name variable if display name is set. */
			if ownerdn ne "" then do;
				ownern = ownerdn;
			end;
		end;

        /* Determine path... */
        /* Get the URI of the tree object associated with the job. */
		rc=metadata_getnasn(uri,"Trees",1,turi);
        /* Set its name as the current value of "path" */
		rc=metadata_getattr(turi,"Name",folder);
		path=folder;
        
        /* Check if that tree object has a parenttree assocation (not a top level folder.) */
        parent_rc=metadata_getnasn(turi,"ParentTree",1,puri); 
        /* If there is a parent tree, get it's name and check it for a parent tree association, adding each folder name to the path variable for as long as it finds parent tree associations. */
		if parent_rc > 0 then do while (parent_rc > 0); 
			rc=metadata_getattr(puri,"Name",pfolder);
			path=cats(pfolder,"\",path);
			parent_rc=metadata_getnasn(puri,"ParentTree",1,puri);
		end;

        /* Add a prefix "\" to complete the path. */
		path=cats("\",path);

        /* Output the record, write it to the log. */
        output;
		put name= path= ownern=;
	end;
run;

proc print data=djobs label; run;