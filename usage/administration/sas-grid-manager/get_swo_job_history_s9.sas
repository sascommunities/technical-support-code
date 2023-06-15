/******************************************************************************/
/* This program queries job information from SAS Grid Manager's Workload      */
/* Orchestrator Daemon using PROC HTTP from the given start date to present.  */
/* The "chunksize" variable sets how many days worth of results to pull at a  */
/* time to avoid issues with pulling a lot of history.                        */
/* Date: 24MAR2022                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Provide connection information. */
%let username = sas;
%let pw = password;
%let limit = 0;
%let startDate = 2022-01-01T00:00:00Z;
%let baseURL = https://grid.demo.sas.com:8901;
%let chunksize = 5;

%macro getjobs();

/* Initialize files to capture HTTP response body and headers. */

filename body temp;
filename headout temp;

/* Calculate an end date that is the chunksize value number of days after the start date. */
%let chunksize=%eval(&chunksize+1);
data _null_;
  x=intnx('dtday', "&startDate"dt,&chunksize);
  y=datetime();
  if x < y then do;
    call symput("endDate",cats(put(x,e8601dt.),"Z"));
  end;
  else do;
    call symdel("endDate","nowarn");
  end;
run;

%if %symexist(endDate) %then %do;

/* Submit a query against the jobs API requesting jobs with a state of "ARCHIVED" (jobs are archived 1 hour after ending). */

  proc http
    URL="&baseURL/sasgrid/api/jobs?state=ARCHIVED%nrstr(&limit)=&limit%nrstr(&firstEndTime)=&startDate%nrstr(&lastEndTime)=&endDate"
    out=body
    headerout=headout
    headerout_overwrite
    webusername="&username"
    webpassword="&pw";
    headers "Accept"="application/vnd.sas.sasgrid.jobs;version=1;charset=utf-8";
  run;

%end;

%else %do;

  proc http
    URL="&baseURL/sasgrid/api/jobs?state=ARCHIVED%nrstr(&limit)=&limit%nrstr(&firstEndTime)=&startDate"
    out=body
    headerout=headout
    headerout_overwrite
    webusername="&username"
    webpassword="&pw";
    headers "Accept"="application/vnd.sas.sasgrid.jobs;version=1;charset=utf-8";
  run;

%end;
/* Deassign the jobinfo libname. */
libname jobinfo;

/* Read in the job info. */
libname jobinfo json fileref=body;

/* See if we have any jobs in the result. This checks the "jobs" table to see if there is an "id" variable present. */

%let dsid=%sysfunc(open(jobinfo.jobs));
%let exists=%sysfunc(varnum(&dsid,id));
%let rc=%sysfunc(close(&dsid));

%put exists=&exists;
%if &exists > 0 %then %do;

/* If we have any jobs in the response, create a table and add the information. */
proc sql;
create table jobs as
  select    a.id,
            b.state, b.queue, b.submitTime, b.startTime, b.endTime, b.processId, b.executionHost, b.exitCode,
            c.name, c.user, c.cmd from
            jobinfo.jobs a, jobinfo.jobs_processinginfo b, jobinfo.jobs_request c where a.ordinal_jobs = b.ordinal_jobs and b.ordinal_jobs = c.ordinal_jobs order by a.id;
quit;

%end;

/* If I set an endDate above (meaning I'm chunking my results), loop until it is unset. */
%do %while ( %symexist(endDate) );

/* Make the startDate the endDate from our last request. */
%let startDate=&endDate;

/* Calculate a new endDate or unset it if this is the last chunk. */
data _null_;
  x=intnx('dtday', "&startDate"dt,&chunksize);
  y=datetime();
  if x < y then do;
    call symput("endDate",cats(put(x,e8601dt.),"Z"));
  end;
  else do;
    call symdel("endDate","nowarn");
  end;
run;

/* Call the endpoint either with or without the endDate defined. */

%if %symexist(endDate) %then %do;

proc http
  URL="&baseURL/sasgrid/api/jobs?state=ARCHIVED%nrstr(&limit)=&limit%nrstr(&firstEndTime)=&startDate%nrstr(&lastEndTime)=&endDate"
  out=body
  headerout=headout
  headerout_overwrite
  webusername="&username"
  webpassword="&pw";
  headers "Accept"="application/vnd.sas.sasgrid.jobs;version=1;charset=utf-8";
run;

%end;

%else %do;

proc http
  URL="&baseURL/sasgrid/api/jobs?state=ARCHIVED%nrstr(&limit)=&limit%nrstr(&firstEndTime)=&startDate"
  out=body
  headerout=headout
  headerout_overwrite
  webusername="&username"
  webpassword="&pw";
  headers "Accept"="application/vnd.sas.sasgrid.jobs;version=1;charset=utf-8";
run;

%end;

/* Deassign the jobinfo libname. */
libname jobinfo;

/* Read in the new job info. */
libname jobinfo json fileref=body;

/* See if we have any jobs in the result. */
%let dsid=%sysfunc(open(jobinfo.jobs));
%let exists=%sysfunc(varnum(&dsid,id));
%let rc=%sysfunc(close(&dsid));

%put exists=&exists;

/* If we do, add them into the table. */
%if &exists > 0 %then %do;
proc sql;
insert into jobs
  select    a.id,
            b.state, b.queue, b.submitTime, b.startTime, b.endTime, b.processId, b.executionHost, b.exitCode,
            c.name, c.user, c.cmd from
            jobinfo.jobs a, jobinfo.jobs_processinginfo b, jobinfo.jobs_request c where a.ordinal_jobs = b.ordinal_jobs and b.ordinal_jobs = c.ordinal_jobs;
quit;
%end;

%end;

%mend getjobs;

%getjobs();

/* Print our data set of the jobs. */
proc print data=work.jobs; run;