/******************************************************************************/
/* This program will extract from Metadata the connections that use each      */
/* Authentication Domain.                                                     */
/* Note: This information is output to the SAS Log, not a data set.           */
/* Date: 08FEB2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Edit with your Metadata host name and credentials. */
options
  metaserver="<hostname>"
  metaport=8561
  metauser="sasadm@saspw"
  metapass="<password>"
  metarepository=Foundation
  metaprotocol=BRIDGE;
/* End Edit */

data _null_; /* Do not create a dataset to house this information. */

/* Define variables. */

	length ad_uri $ 256 ad_id $ 256 ad_name $ 256 con_uri $ 256 con_id $ 256 con_name $ 256;

/* Initialize variables. */

	call missing(ad_uri,ad_id,con_uri,con_id,con_name,ad_name);
	n=1;
	m=1;

/* Count the number of authentication domains. */

	adrc=metadata_getnobj("omsobj:AuthenticationDomain?@Id contains '.'",n,ad_uri);
do while(adrc>0);

/* For each authentication domain, get it's attributes. */

	arc=metadata_getattr(ad_uri,"Id",ad_id); 
	arc=metadata_getattr(ad_uri,"Name",ad_name);
	put "--- TCP/IP Connections used by " ad_name " Authentication Domain ---";
	objrc=metadata_getnobj("omsobj:TCPIPConnection?TCPIPConnection[Domain/AuthenticationDomain[@Id='"||ad_id||"']]",m,con_uri);

	/* For each TCP/IP connection associated with the authentication domain, get attributes. */

		do while(objrc>0);
			arc=metadata_getattr(con_uri,"Id",con_id);
			arc=metadata_getattr(con_uri,"Name",con_name);
			put m con_id con_name;
			m+1;
			objrc=metadata_getnobj("omsobj:TCPIPConnection?TCPIPConnection[Domain/AuthenticationDomain[@Id='"||ad_id||"']]",m,con_uri);
		end;
	m=1;
	put "--- SAS Client Connections using the " ad_name " Authentication Domain ---";
	objrc=metadata_getnobj("omsobj:SASClientConnection?SASClientConnection[Domain/AuthenticationDomain[@Id='"||ad_id||"']]",m,con_uri);

		/* For each SAS client connection associated with the authentication domain, get attributes. */

			do while(objrc>0);
			arc=metadata_getattr(con_uri,"Id",con_id);
			arc=metadata_getattr(con_uri,"Name",con_name);
			put m con_id con_name;
			m+1;
			objrc=metadata_getnobj("omsobj:SASClientConnection?SASClientConnection[Domain/AuthenticationDomain[@Id='"||ad_id||"']]",m,con_uri);
		end;
	n+1;
	adrc=metadata_getnobj("omsobj:AuthenticationDomain?@Id contains '.'",n,ad_uri);
end;
run;
