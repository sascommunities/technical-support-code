/******************************************************************************/
/* This program uses PROC IOMOPERATE to modify the email settings without     */
/* requiring a restart of the Metadata Server to draw this information from   */
/* the omaconfig.xml/sasv9.cfg files in SASMeta/MetadataServer. Note that the */
/* files must still be modified for the changes to survive a restart of the   */
/* Metadata Server process.                                                   */
/* Date: 05APR2017                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Metadata Server Connection Settings (Metadata Server and password for unrestricted account.) */
%let metaserv=<metadata_host>;
%let metapw=<sasadm_password>;

/* New email settings. */
%let mailhost=<smtp_server_hostname>;
%let mailport=25;
%let alertemail=<email_address_to_send_alerts>;
/* End edit. */

options metaserver="&metaserv"
		metaport=8561
		metauser="sasadm@saspw"
		metapass="&metapw"
		metarepository=Foundation
		metaprotocol=Bridge;

/* Gather current email settings. */

PROC METADATA
	method=status
	in="<OMA ALERTEMAIL="""" EMAILHOST="""" EMAILPORT="""" EMAILID="""" SERVER_STARTED="" "" CURRENT_TIME="" "" SERVERSTARTPATH="" ""/>"
	NOREDIRECT;
RUN;

/* Send an alert email with the current settings. */
PROC METAOPERATE
	action=refresh
	options="<OMA ALERTEMAILTEST=""Please disregard. This is only a test.""/>" 
	noautopause;
RUN;

/* Apply new options for the email alert and send an alert with the new settings. */

PROC METAOPERATE
	action=refresh
	options="<OMA 
			ALERTEMAIL=""&alertemail"" 
			EMAILHOST=""&mailhost"" 
			EMAILPORT=""&mailport""
			/>
			<OMA ALERTEMAILTEST=""Please disregard. This is only a test (new settings).""/>"
	noautopause noredirect;
RUN;

/* Gather current email settings again (showing the update was made). */

PROC METADATA
	method=status
	in="<OMA ALERTEMAIL="""" EMAILHOST="""" EMAILPORT="""" EMAILID="""" SERVER_STARTED="" "" CURRENT_TIME="" "" SERVERSTARTPATH="" ""/>"
	NOREDIRECT;
RUN;
