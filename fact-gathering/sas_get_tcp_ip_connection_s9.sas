/************************************************************
  Date: 13Dec2013
  This script is used to get Url's from Metadata.
  It lists Internal and External Connections (except SASThemes)

  USAGE : Update metaserver &  Update metapass in the code below 
  under options and run this on SAS Studio or Enterprise guide. 

  NOTE : This program only works on SAS 9.4 .

************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

options 
metaserver="localhost" 
metaport=8561
metauser="sasadm@saspw" 
metapass="xxxxxxx";

data tcpip;
	keep name port host protocol service;

	length port host protocol objid service uri name $255;
  	nobj=0;
  	n=1;
    do while (nobj >= 0);
  		nobj=metadata_getnobj("omsobj:TCPIPConnection?@Name='Connection URI' or @Name='External URI'",n,uri);

		if (nobj >= 0) then do;
			rc=metadata_getattr(uri,"Name",name);
			if trim(name)='Connection URI' then name="Internal URI";

			rc=metadata_getattr(uri,"CommunicationProtocol",protocol);
			rc=metadata_getattr(uri,"HostName",host);
			rc=metadata_getattr(uri,"Port",port);
			rc=metadata_getattr(uri,"Service",service);
			*call cats(protocol,'://',host,':',port,service);
			put name protocol"://"host":"port service;
			output;
		end ;
		n = n + 1;
	end;	
run;

proc sort data=tcpip out=sorted;
	by service;
run;

proc print data=sorted;
	var name protocol port host service;
	title  'Internal and External Connections (except SASThemes)';
	title2 'Listed by Service';
run;
