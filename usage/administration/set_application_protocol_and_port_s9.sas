/*******************************************************************************/
/* This program will locate web connection info defined in Metadata and update */
/* the protocol and port. This can be useful when switching from HTTP to HTTPS */
/* after the initial deployment.                                               */
/* Date: 26SEP2019                                                             */
/*******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define macro variables for Metadata connection information and the protocols and ports that need changing.*/
%let metaserve=meta.demo.sas.com;
%let metaport=8561;
%let userid=sasadm@saspw;
%let pass=password;
%let oldprotocol='http';
%let newprotocol='https';
%let oldport='7980';
%let newport='8343';
/*End edit. */

/* Define Metadata connection information. */
options metaserver="&metaserve"
metaport=&metaport
metaprotocol='bridge'
metauser="&userid"
metapass="&pass"
metarepository='Foundation'
metaconnect='NONE'
;

/* Take an ad-hoc Metadata backup. */

PROC METAOPERATE ACTION=refresh options="<BACKUP COMMENT='METAOPERATE backup'/>" noautopause;
RUN;

/* Define a search that only returns objects defined with the old protocol and port. */

%let query="omsobj:TCPIPConnection?@CommunicationProtocol=&oldprotocol and @Port=&oldport";

/* For each, change the protocol to the new one. */

data _null_;
	length type id uri $ 50 ;
	call missing (of _character_);
	count=metadata_resolve(&query,type,id);
	put "NOTE: Found " count "connections to update.";
	if count > 0 then do n=1 to count;
		rc=metadata_getnobj(&query,n,uri);
		rc=metadata_setattr(uri,"CommunicationProtocol",&newprotocol);
		rc=metadata_setattr(uri,"Port",&newport);
	end;
run;

