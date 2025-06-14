/******************************************************************************/
/* This program will find all of the ForeignKey FKobjects that do not have a  */
/* PartnerUniqueKey association, and will REPORT on them and optionally       */
/* DELETE them based upon the setting of the MODE macro variable.             */
/* Date: 12JUN2025                                                            */
/******************************************************************************/

/* Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* TODO: Edit with connection information for the Metadata Server. */

*options metaserver="meta.demo.sas.com"
        metaport=8561
        metauser="sasadm@saspw"
        metapass="Password"
        metarepository='Foundation'
        ;

/* End edit. */

/* TODO: Set MODE to REPORT or DELETE */
%let MODE=REPORT;

data _null_;
    /* Initialize variables. */
	length FK_id PT_id $17 type FK_uri PT_uri $50 PT_engine $64 PT_name $32 FK_name $60;
	call missing ( of _character_ );
  retain mode "&MODE";

  /* Define a query for ForeignKey FKobjects that do not have a PartnerUniqueKey association */
	FK_obj="omsobj:ForeignKey?ForeignKey[not(PartnerUniqueKey/*)]";

  /* Determine how many foreign key objects meet the criteria */
	FK_Count=metadata_resolve(FK_obj,type,FK_id);
	put "NOTE: Found " FK_Count "ForeignKey objects that do not have an associated PartnerUniqueKey";

  /* If any were found, iterate through each one to get the attributes and associations */
	if FK_Count > 0 then do i = 1 to FK_Count;
    /* Get the URI for the nth ForeignKey found */
		FK_rc=metadata_getnobj(FK_obj,i,FK_uri);

    /* Get the name and ID of the ForeignKey FKobject */
		FK_rc=metadata_getattr(FK_uri,"Name",FK_name);
    FK_rc=metadata_getattr(FK_uri,"Id",FK_id);
  
    /* get the table name and id this ForeignKey is associated with */
    PT_rc=metadata_getnasn(FK_uri,"Table",1,PT_uri);
		if PT_rc > 0 then do;
       /* Get the name and ID of the table. */
			PT_rc=metadata_getattr(PT_uri,"SASTableName",PT_name);
      PT_rc=metadata_getattr(PT_uri,"Id",PT_id);
    end;

    /* REPORT and DELETE */
    put "NOTE: Found foreign key: " FK_name "with id: " FK_id "for table: " PT_name "with id: " PT_id;
    if mode = "DELETE" then do;
      FK_rc = metadata_delobj(FK_uri);
      if FK_rc then put 'ERROR: metadata_delobj failed with return code ' FK_rc;
      else put 'NOTE: Foreign key successfully deleted'; 
    end;
	end;
run;