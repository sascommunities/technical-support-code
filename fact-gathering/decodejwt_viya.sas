/* Macro to decode the contents of the JWT in the supplied environment variable. */
/* Call this macro using SAS_CLIENT_TOKEN or SAS_SERVICES_TOKEN depending on the  */
/* token you wish to examine. For example: %decodejwt(SAS_CLIENT_TOKEN);*/

/* Date: 26FEB2025 */

/* Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Begin the macro definition. */
%macro decodejwt(tokenvar);

/* Define a temp file to hold our JSON output. */
filename decode temp;

/* Capture the initial value of the quotelenmax option */
%let quotelenmax=%sysfunc(getoption(quotelenmax));

/* As the token is often over 292 characters, disable the warning. */
options noquotelenmax;

/* Pull the contents of the supplied environment variable into a macro variable. */
%let rawtoken=%sysget(&tokenvar);

/* DATA Step to measure our token substring. */
data _null_;
	/* Set the starting location to the first period + 1 */
	sloc=1 + find("&rawtoken",'.');
	call symput("sloc",trim(left(put(sloc,8.))));
    /* Set the end location to the second period. */
	eloc=find("&rawtoken",'.',sloc);
	call symput("eloc",trim(left(put(eloc,8.))));
    /* Calculate the length of the token substring. */
	len=eloc-sloc+2;
	call symput("len",trim(left(put(len,8.))));
run;

/* DATA Step to extract out token substring for decode. */

data _null_;
    /* We store the token substring + '==' to the token variable */
    /* len was set in the previous data step to that length. */
    length token $ &len;

    /* Calculate the length of the substring we want to extract. */
    len=&eloc-&sloc;

    /* Pull the substring into the token variable, adding the '==' suffix. */
	token=cats(substr("&rawtoken",&sloc,len),"==");
    
    /* Replace some characters */
	token=tranwrd(token,"_","\");
	token=tranwrd(token,"-","+");

	/* put the transformed token substring into a macro variable */
	call symput("token",token);
run;

/* DATA Step to base64 decode the token substring, outputing the JSON contents to our temp file. */
data _null_;
    
    /* Define the fileref to output the decoded string. */
	file decode;

	/* Set the token variable to our encoded string. */
	token="&token";	

	/* Decode the string using the base64 informat */
	decode=input(token,$base64x&len..);

    /* Output the JSON string to our temp file */
	put decode;
run;

/* Read in our temp file JSON using the JSON libname engine. */
libname decode json;

/* DATA Step to output the details to the log file.  */
data _null_;
	
	/* Read in the ROOT table of the DECODE library. */
	set decode.root;

	/* Calculate token life, in seconds. */
	life=exp-iat;
	/* Calculate token life, in hours. */
    hours=life/3600;

	/* Convert expiration epoch time to a SAS datetime. */
	expire = dhms('01jan1970'd, 0, 0, exp);
	
	/* Convert issued epoch time to a SAS datetime. */
	issued =  dhms('01jan1970'd, 0, 0, iat);

	/* Specify the format for these new values. */
  	format expire issued datetime20.;  

	/* Output the details from the token. */
    if _N_ = 1 then put "NOTE: Token Details:";
	put "NOTE- Client ID: " client_id;
    put "NOTE- External ID: " ext_id;
    put "NOTE- Grant Type: " grant_type;
	put "NOTE- User: " user_name;
	put "NOTE- Email: " email;
    put "NOTE- Origin: " origin;
	put "NOTE- Your issued token life is " life "seconds. (" hours " hours)";
	put "NOTE- Token issued: " issued;
	put "NOTE- Token expires: " expire;
run;

/* DATA Step to output authority and scope details from the token. */
data _null_;
	/* Read in the ALLDATA table from the DECODE library. */
	set decode.alldata;
	
	/* Output the authorities array, if present. */
	if P1 = 'authorities' and V = 0 then put "NOTE: Authorities in Token:";
	if P1 = 'authorities' and V = 1 then put "NOTE-" Value;

	/* Output the scope array, if present. */
    if P1 = 'scope' and V = 0 then put "NOTE: Scopes in Token:";
    if P1 = 'scope' and V = 1 then put "NOTE-" Value;
run;

/* Reset the quotelenmax option */
options &quotelenmax;

/* Dereference our library and file. */
libname decode;
filename decode;
%mend;

/* Run the macro */
%decodejwt(SAS_CLIENT_TOKEN);