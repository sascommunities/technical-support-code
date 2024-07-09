/******************************************************************************/
/* This program will delete a supplied list of users from Metadata.           */
/* Date: 01AUG2023                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved. */
/* SPDX-License-Identifier: Apache-2.0 */

/* Define Metadata connection information */

options metaserver='meta.example.com'
        metaport=8561
        metaprotocol='bridge'
        metauser='sasadm@saspw'
        metapass='password'
;
 
/* DATA Step to create a data set of users to delete. */
 
data work.delusers;
	infile datalines truncover;
    length username $ 255;
    call missing (of _character_);
    input username $1-255;
    datalines;
  deltest
  deltest1
  deltest2
  del test3
;;
run;
 
/* DATA Step to delete users supplied in dataset above. */
data _null_;

    /* Read in the data set. */
    set work.delusers;

    /* Build a URI from the supplied user name. */
    obj="omsobj:Person?@Name='"||trim(username)||"'";

    /* Delete the Logins associated with the user. */
    rc=metadata_delassn(obj,"Logins");
    
    /* Check if the delete of Logins was successful. */

    if rc ne 0 then do;
        /* Throw an error if the login delete action failed. */
        put "ERROR: Failed to delete associated logins for user " username ". " rc=;
        end;
        /* If deleting logins was successful, move on to deleting the user. */
    else do;
        /* Write a note to the log indicating the delete of logins was successful. */
        put "NOTE: Successfully deleted logins associated with user " username". Attempting to delete user.";

        /* Delete the user object. */
        rc=metadata_delobj(obj);

        /* Check if delete was successful. */
        if rc ne 0 then do;
        
            /* If not, throw an error. */
            put "ERROR: Failed to delete user " username ". " rc=;
        end;

            /* If so, note that delete was successful. */
        else put "NOTE: Successfully deleted user " username ".";
    end;
run;