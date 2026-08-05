# This code exports a specified report as a PNG image at the desired resolution using the report ID.
# Date: 31JUL2026
#
# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

/* Specify host and Report ID. */
%let baseurl=https://hostname;
%let reportId=<report_id>;

filename req temp;  /* Temporary file for the request body */
filename report "/path/to/report/<Export Image name>.png";

/* Write the JSON request body to a file */
data _null_;
    file req;
run;

/* Make the HTTP GET request */
proc http
    method="GET"
    url="&baseurl/visualAnalytics/reports/&reportId/png?size=1024px,768px"
    in=req
    out=report
    ct="application/vnd.sas.selection+json, application/json, application/vnd.sas.error+json, application/json, image/png"
   AUTH_ANY
    OAUTH_BEARER=SAS_SERVICES;
run;

