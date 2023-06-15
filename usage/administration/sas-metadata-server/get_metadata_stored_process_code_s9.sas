/******************************************************************************/
/* This program will extract from metadata any source code for a stored       */
/* process stored in metadata, and output it to the log, as well as           */
/* optionally editing the code in place to replace a word.                    */
/* Date: 03DEC2018                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

data _null_;

/* Initialize the variables. */

	length program newprog $ 32587 type id $ 50 sp_uri $ 38 note_uri $ 34 note_name $ 255; 
	call missing(of _character_);

/* Define a query that will return only Stored Process objects with an associated source code TextStore object. */
	
	sp_obj="omsobj:ClassifierMap?ClassifierMap[@PublicType='StoredProcess'][Notes/TextStore[@Name='SourceCode']]"; 
	
/* Count how many objects meet that query. */
	
	sp_count=metadata_resolve(sp_obj,type,id);
	
/* If some exist, gather their information. */

	if sp_count > 0 then do i=1 to sp_count;
	
/* Get the URI for each Stored Process object found that matches the query. */
	
		rc=metadata_getnobj(sp_obj,i,sp_uri); 
		
/* Count how many notes are associated with the object. */
		
		note_count=metadata_getnasn(sp_uri,"Notes",1,note_uri); 
		
/* If some exist, get their attributes. */
		
		if note_count > 0 then do j=1 to note_count; 

		
			rc=metadata_getnasn(sp_uri,"Notes",j,note_uri); /* get the URI of the note. */
			rc=metadata_getattr(note_uri,"Name",note_name); /* get the name of the note. */
			
/* If the Note's name is "SourceCode", get it's "StoredText" attribute. */

			if note_name="SourceCode" then do; 
				rc=metadata_getattr(note_uri,"StoredText",program); 				
				put;
				put note_uri=;	/* Print the URI to the Log */
				put;
				put program=; /* Print the program to the log. */		
				
				/* Optional find and replace code. replace old_text and new_text with the word to replace. */
				*newprog=tranwrd(program,'old_text','new_text');
				*rc=metadata_setattr(note_uri,"StoredText",newprog);				
			end;
		end;
	end;
run;