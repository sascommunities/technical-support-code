/* Example code to add an email addresses and phone numbers to users in a SAS Metadata Server.
   This code assumes you have the necessary permissions to modify user metadata.
   It checks if the email or phone number already exists for the user before adding it.
   If the user does not exist, it skips that user.
   The search is performed based on "userid" in the "users" dataset, which is matched agains the
   user's "name" attribute in Metadata, which may be different from their login ID.
*/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Connect to metadata */
options metaserver='meta.example.com'
        metaport=8561
        metaprotocol='bridge'
        metauser='sasadm@saspw'
        metapass='password'
        metarepository='Foundation'
        metaconnect='NONE';

/* Build a sample data set with User ID, email address, and phone numbers. */
data users;
    length userid email phone $ 128;
    infile datalines delimiter=',';
    input userid $ email $ phone $;
    datalines;
sasdemo,sasdemo@example.com,+1 123-456-7890
sasuser,sasuser@example.com,+1 456-789-0123
;;
run;

/* Loop through each user in the dataset */
data _null_;
    length type $ 6 id $ 17 uuri $ 31 euri $ 30 cemail $ 128 cphone $ 128;
    call missing(type, id, uuri, euri, cemail, cphone);
    set users;
    emailset=0;
    phoneset=0;
    /* Find the user in Metadata */
    rc=metadata_resolve("omsobj:Person?Person[@Name='" || trim(userid) || "']", type, id);
    if rc < 0 then do;
        put "Error resolving user " userid ": METADATA_RESOLVE returned " rc=;
        stop; /* Exit the data step if there is an error */
    end;

    /* If the user is found */
    if rc=1 then do;

        /* Build the URI  for the person */
        uuri=cats("OMSOBJ:Person/",id);

        /* Check if they already have any email address associated. */
        email_count=metadata_getnasn(uuri,"EmailAddresses",1,euri);
        if email_count = -4 then email_count=0; /* -4 means out of range, so set count to 0 */
        if email_count < 0 then do;
            put "Error getting email addresses for user " userid ": rc=" email_count;
            return; /* Exit the data step if there is an error */
        end;
        put "Found " email_count "existing email addresses for user " userid;

        /* Loop through the email addresses to see if the one we want to add already exists */
        if email_count > 0 then do i=1 to email_count while(emailset=0);
            
            /* See if one of the emails is the same as the one we want to add. */
            rc=metadata_getnasn(uuri,"EmailAddresses",i,euri);
            rc=metadata_getattr(euri,"Address",cemail);
            if trim(cemail) = trim(email) then do;
                put "User " userid "already has email address " email;
                emailset=1;
            end;
        end;

        /* If the email is not already present, create a new email object and associate it to the user. */
        if emailset=0 then do;
            put "Creating new email address for user " userid ": " email;
            /* Create an email object */
            rc=metadata_newobj("Email",euri,cats(userid," -email"));
            /* Add attributes to the object */
            rc=metadata_setattr(euri,"Address",email);
            rc=metadata_setattr(euri,"EmailType","Work");
            rc=metadata_setattr(euri,"IsHidden","0");
            rc=metadata_setattr(euri,"UsageVersion","0");
            /* Associate the email with the user */
            rc=metadata_setassn(uuri, "EmailAddresses", "APPEND", euri);
        end;

        /* Check if they already have any phone numbers associated. */
        phone_count=metadata_getnasn(uuri,"PhoneNumbers",1,euri);
        if phone_count = -4 then phone_count=0; /* -4 means out of range, so set count to 0 */
        if phone_count < 0 then do;
            put "Error getting phone numbers for user " userid ": rc=" phone_count;
            return; /* Exit the data step if there is an error */
        end;
        put "Found " phone_count " existing phone numbers for user " userid;
        if phone_count > 0 then do i=1 to phone_count while(phoneset=0);
            /* See if one of the phone numbers is the same as the one we want to add. */
            rc=metadata_getnasn(uuri,"PhoneNumbers",i,euri);
            rc=metadata_getattr(euri,"Number",cphone);
            if trim(cphone) = trim(phone) then do;
                put "User " userid "already has phone number " phone;
                phoneset=1;
            end;
        end;
        /* If the phone number is not already present, create a new phone object and associate it to the user. */
        if phoneset=0 then do;
            put "Creating new phone number for user " userid ": " phone;
            /* Create a phone object */
            rc=metadata_newobj("Phone",euri,cats(userid," -phone"));
            /* Add attributes to the object */
            rc=metadata_setattr(euri,"Number",phone);
            rc=metadata_setattr(euri,"PhoneType","Work");
            rc=metadata_setattr(euri,"IsHidden","0");
            rc=metadata_setattr(euri,"UsageVersion","0");
            /* Associate the phone with the user */
            rc=metadata_setassn(uuri, "PhoneNumbers", "APPEND", euri);
        end;
    end;
    /* If the user is not found, skip */
    else if rc=0 then do;
        put "User " userid "not found in Metadata. Skipping.";
    end;
    /* If there is an error resolving the user */
    else if rc < 0 then do;
        put "Error resolving user " userid ": " rc;
    end;
    else do;
        put "Found more than one user matching query for user " userid rc=;
    end;
run;

