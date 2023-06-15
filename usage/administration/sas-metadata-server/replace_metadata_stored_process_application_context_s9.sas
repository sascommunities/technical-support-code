/******************************************************************************/
/* This program will change the execution application server for every stored */
/* process from the context defined in the oldcontext macro variable to that  */
/* defined in the newcontext variable.                                        */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 29MAR2023                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define metadata connection information. */
options metaserver="meta.example.com"
		metaport=8561
		metauser="sasadm@saspw"
		metapass="password"
		;

/* Set the old and new contexts. */
%let oldcontext=SASApp1;
%let newcontext=SASApp2;

/* End edit. */

data _null_;

/* Initialize variables */
	length type id spuri conuri $ 50 name $ 255;
	call missing (of _character_);

/* Confirm the old context exists. */
	rc=metadata_resolve("omsobj:ServerContext?ServerContext[@Name = '&oldcontext']]",type,id);
	if rc ne 1 then do;
		put "ERROR: Old context &oldcontext not defined in metadata. " rc=;
		stop;
	end;

/* Confirm the new context exists. */
	rc=metadata_resolve("omsobj:ServerContext?ServerContext[@Name = '&newcontext']]",type,id);
	if rc ne 1 then do;
		put "ERROR: New context &newcontext not defined in metadata. " rc=;
		stop;
	end;

	/* Get the URI for the new context. */
	rc=metadata_getnobj("omsobj:ServerContext?ServerContext[@Name = '&newcontext']]",1,conuri);

	obj="omsobj:ClassifierMap?ClassifierMap[@PublicType='StoredProcess'][ComputeLocations/ServerContext[@Name = '&oldcontext']]";

	/* Find all stored processes that use the old context */
	rc=metadata_resolve(obj,type,id);
	put "NOTE: Found " rc "Stored Processes associated with context &oldcontext";

	/* If any were found, iterate through them all */
	if rc > 0 then do i = 1 to rc;
		/* Get the URI for the stored process */
		rc=metadata_getnobj(obj,i,spuri);
		rc=metadata_getattr(spuri,"Name",name);

		put "NOTE: Attempting to update stored process " name "to use context &newcontext.";

        /* Set rc=1 so the condition below will indicate failure if the setassn line remains commented out */
		rc=1;

        /* Replace the association with the new context */
		/* Uncomment this line to perform the write.  */
		*rc=metadata_setassn(spuri,"ComputeLocations","REPLACE",conuri);

		/* Confirm we were successful. */
		if rc ne 0 then put "ERROR: Failed to replace association on Stored Process. Did you uncomment the metadata_setassn function?" spuri=;
		else put "NOTE: Successfully updated stored process " spuri "to use context " conuri;
	end;
run;