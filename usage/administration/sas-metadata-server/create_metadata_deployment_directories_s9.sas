/******************************************************************************/
/* This program will add a list deployment directories to Metadata for a      */
/* defined context.                                                           */
/* Date: 14JUN2019                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

 /* Define connection to Metadata. */
options
	metaserver="meta.demo.sas.com"
	metaport=8561
	metauser="sasadm@saspw"
	metapass="password"
	metarepository=Foundation
	metaprotocol=BRIDGE;

/* Define the context to attach the deployment directories. */
%let appcontext = SASApp;

/* Create a dataset with each deployment directory name and path. */
data depdirs;
	length Name Path $ 255;
	input Name Path;
	datalines;
	DeploymentDir1 /tmp/depdir1
	DeploymentDir2 /tmp/depdir2
	;;
run;
/* End edit. */

data _null_;

/* Initialize variables. */
length type id appuri diruri $ 255; 
call missing (of _character_);

/* Define query for context. */
appobj = "omsobj:ServerContext?@Name='&appcontext'";

/* Check for the existence of the context. */
rc=metadata_resolve(appobj,type,id);

/* If the context doesn't exist, throw an error and end the program. */
if rc ne 1 then do;
put "ERROR: A single context named &appcontext not found.";
stop;
end;

/* Read in the data set of deployment directories. */
set depdirs;

/* For each one, create the directory object as a child of the context defined above. */
rc=metadata_newobj("Directory",diruri,Name,"Foundation",appobj,"DataPackages");

/* Add the attribute defining the path. */
rc=metadata_setattr(diruri,"DirectoryName",Path);

/* Add some required attributes. */
rc=metadata_setattr(diruri,"UsageVersion","0");
rc=metadata_setattr(diruri,"IsRelative","0");

run;