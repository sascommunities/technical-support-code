# This code retrieves information for a specific report using its report ID.
# Date: 31JUL2026
#
# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

/* Specify host and Report ID. */

%let baseurl=https://hostname;
%let reportId=<report_id>;

filename resp temp; /* Temporary file to store response */
filename req temp;  /* Temporary file for the request body */

/* Write the JSON request body to a file */
data _null_;
    file req;
run;

/* Make the HTTP GET request */
proc http
    method="GET"
    url="&baseurl/reports/reports/&reportId"
    in=req
    out=resp
    ct="application/vnd.sas.selection+json, application/json, application/vnd.sas.error+json"
   AUTH_ANY
    OAUTH_BEARER=SAS_SERVICES;
run;

libname perms json fileref=resp;
proc print data=perms.alldata noobs label;
    title "Report infromation";
run;
