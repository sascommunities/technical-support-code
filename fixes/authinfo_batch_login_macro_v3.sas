/*********************************************************************/
/* Macro to log in to Viya using authinfo file.                      */
/*                                                                   */
/* This can be helpful when running SAS code from the command line   */
/* that requires access to information from the Viya microservices   */
/* like assigning a library with the AUTHDOMAIN option.              */
/*                                                                   */
/* The macro will log in to Viya using the credentials in a standard */
/* authdomain file and set the resulting token to the environment    */
/* variable SAS_VIYA_TOKEN.                                          */
/* This macro requires the SERVICESBASEURL option be set.            */
/* Date: 17FEB2022                                                   */
/*********************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

%macro gettoken();

/* Get the current value of some options to change. */
%local user pass nosource nosource2 nonotes nomprint nomlogic nosymbolgen noquotelenmax;
%let nosource=%sysfunc(getoption(nosource));
%let nosource2=%sysfunc(getoption(nosource2));
%let nonotes=%sysfunc(getoption(nonotes));
%let nomprint=%sysfunc(getoption(nomprint));
%let nomlogic=%sysfunc(getoption(nomlogic));
%let nosymbolgen=%sysfunc(getoption(nosymbolgen));
%let noquotelenmax=%sysfunc(getoption(noquotelenmax));

options nosource nosource2 nonotes nomprint nomlogic nosymbolgen;

/* Make the variables local so I can't look at them later. */
%local user pass;

/* Pull in the value of the authinfo option and use this if defined. */
%let authinfo=%sysfunc(getoption(authinfo));

/* If not defined in the option, check the environment variable AUTHINFO */
%if %length(&authinfo) = 0 %then %do;
    %if (%sysfunc(sysexist(AUTHINFO))) %then %do;
        %let authinfo=%sysget(AUTHINFO);
    %end;
%end;

/* If not defined in the environment variable AUTHINFO, check the environment variable NETRC */
%if %length(&authinfo) = 0 %then %do;
    %if (%sysfunc(sysexist(NETRC))) %then %do;
        %let authinfo=%sysget(NETRC);
    %end;
%end;

/* If it's not defined, define it to the default (HOME/.authinfo) */
%if %length(&authinfo) = 0 %then %do;
    %if (&SYSSCP = WIN) %then %do;
        %let authinfo=%sysget(USERPROFILE)\_authinfo;
    %end;
    %else %do;
        %let authinfo=%sysget(HOME)/.authinfo;
    %end;
%end;

/* Check if the file exists. */

%if (%sysfunc(fileexist(&authinfo))) %then %do;

    /* Check if servicesbaseurl is defined. */
    %let baseurl=%sysfunc(getoption(servicesbaseurl));

    %if %length(&baseurl) = 0 %then %do;
    %put ERROR: SERVICESBASEURL option not defined;
    options &nosource &nosource2 &nonotes &nomprint &nomlogic &nosymbolgen;
    %abort;
    %end;

    /* Read in the authinfo file. */

    filename authinfo "&authinfo";

    /* Authinfo file lines can be in a few formats:  */
    /* default user <user> password <password> */
    /* host <hostname> user <user> password <password> */
    /* host <hostname> port <port> user <user> password <password> */

    /* We need to be able to handle each of these when reading in the file */
    /* and also get host/port information from the baseurl defined. */

    data authinfo;
        length line $ 1024 host username pass $ 255 port 8;
        infile authinfo;
        input;
        line=strip(_infile_);
        if line="" then;
        if find(line,'default') then do;
            host="default";
            port=0;
            username=scan(substr(line,findw(line,'user')+5),1," ");
            pass=scan(substr(line,findw(line,'password')+9),1," ");
        end;
        else if find(line,'port') then do;
            host=scan(substr(line,findw(line,'host')+5),1," ");
            port=scan(substr(line,findw(line,'port')+5),1," ");
            username=scan(substr(line,findw(line,'user')+5),1," ");
            pass=scan(substr(line,findw(line,'password')+9),1," ");
        end;
        else do;
            host=scan(substr(line,findw(line,'host')+5),1," ");
            port=0;
            username=scan(substr(line,findw(line,'user')+5),1," ");
            pass=scan(substr(line,findw(line,'password')+9),1," ");
        end;
    run;


    /* Get the host and port combination from the servicesbaseurl option we captured into the baseurl macro variable. */

    /* If no port is defined we will use the defaults based on the supplied protocol (http or https.) */

    data _null_;
        length port 8;
        prefix=substr("&baseurl",1,5);
        if prefix="https" then do;
            port=443;
            host=substr("&baseurl",9);
        end;
        else do;
            port=80;
            host=substr("&baseurl",8);
        end;
        rc=countc("&baseurl",":");
        if rc=2 then do;
            port=input(scan("&baseurl",-1,":"),5.);
            host=scan("&baseurl",-2,":/");
        end;
        call symput("host",trim(host));
        call symput("port",strip(put(port,5.)));
    run;

    /* Pull the user and password from the authinfo dataset that matches our host port combination, or default if none matches. */

    /* Check if we have a listing where host and port match */

    proc sql noprint;
        select count(username) into :match from work.authinfo where host="&host" and port=&port;
    quit;

    %if &match = 1 %then %do;
    /* If so, grab the user and pass into variables. */
        proc sql;
            select strip(username) into :user from work.authinfo where host="&host" and port=&port;
            select strip(pass) into :pass from work.authinfo where host="&host" and port=&port;
        quit;
    %end;
    /* If not, check if we have a host match with port = 0 */
    %else %do;
        proc sql noprint;
            select count(username) into :match from work.authinfo where host="&host" and port=0;
        quit;
        %if &match = 1 %then %do;
        /* If so, grab the user and pass into variables. */
        proc sql noprint;
            select strip(username) into :user from work.authinfo where host="&host" and port=0;
            select strip(pass) into :pass from work.authinfo where host="&host" and port=0;
        quit;
        %end;
        /* If not, check if there is a default user/pass. */
        %else %do;
            proc sql noprint;
                    select count(username) into :match from work.authinfo where host="default" and port=0;
            quit;
            %if &match = 1 %then %do;
                /* If so, grab the user and pass into variables. */
                proc sql noprint;
                    select strip(username) into :user from work.authinfo where host="default";
                    select strip(pass) into :pass from work.authinfo where host="default";
                quit;
            %end;
            %else %do;
                %put ERROR: No credentials found that match host &host:&port and no default.;
                options &nosource &nosource2 &nonotes &nomprint &nomlogic &nosymbolgen;
                %abort;
            %end;
        %end;
    %end;

    /* Delete our authinfo dataset. */
    proc delete data=work.authinfo; run;

    /* Confirm we have a user and password variable defined. */

    %if (%sysfunc(symexist(user)) and %sysfunc(symexist(pass))) %then %do;

        /* If so, try to log in with it. */

        /* URL Encode the credentials in case we have some special characters. */
        %let user=%sysfunc(urlencode(&user));
        %let pass=%sysfunc(urlencode(&pass));

        /* Init some files for the PROC HTTP output. */
        filename headout temp;
        filename resp temp;
        filename init temp;

        /* Prevent warning if the bearer token is really long. */
        options noquotelenmax;

        /* Get an authentication token. */
        proc http url="&baseurl/SASLogon/oauth/token" in="grant_type=password%nrstr(&username)=&user.%nrstr(&password)=&pass"
            out=resp headerout=headout HEADEROUT_OVERWRITE webusername="sas.ec" webpassword="";
            headers "Accept"="application/json";
        run;

        libname resp;
        /* Read in the response */
        libname resp json fileref=resp;

        /* Set the access token in the response to a macro variable called "bearer". */
        data _null_;
            set resp.alldata;
            if P1="access_token" then call symput("bearer",trim(value));
        run;
        options set=SAS_VIYA_TOKEN="&bearer";
        options &noquotelenmax;

    %end;
    %else %do;
        %put ERROR: No user and password found.;
        options &nosource &nosource2 &nonotes &nomprint &nomlogic &nosymbolgen;
        %abort;
    %end;
%end;

%else %do;
%put ERROR: AUTHINFO file &authinfo does not exist.;
options &nosource &nosource2 &nonotes &nomprint &nomlogic &nosymbolgen;
%abort;
%end;

options &nosource &nosource2 &nonotes &nomprint &nomlogic &nosymbolgen;

%mend gettoken;