/******************************************************************************/
/* This program will set the supplied loggers and levels on all SAS Workload  */
/* Orchestrator nodes using basic or negotiate authentication.                */
/* Date: 23MAR2022                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* --- OMIT THIS SECTION IF USING NEGOTIATE (SSPI) AUTHENTICATION --- */
/* --- AND COMMENT OUT THE AUTHORIZATION HEADER IN THE PROC HTTP BELOW.  --- */

%let username = username;
%let pw = password;

/* This encodes the username:password in base64 and stores it in the auth macro variable */
data _null_;
auth=put("&username:&pw",$base64x64.);
call symput("auth",auth);
run;
/* ------------------------------------------------------------ */

/* Provide connection information. */
%let baseURL = https://grid-master.demo.sas.com:8901;

/* Define the loggers we want to set and at what level into a dataset. */
/* "NULL" instructs to inherit from the parent. */

data work.loglevel;
length logger $ 255 level $ 10;
call missing (of _character_);
input logger $ level $;
datalines;
  App.Grid.SGMG.Log trace
  App.Grid.SGMG.Log.Util.Lock info
  Audit.Authentication trace
  App.tk.http.server trace
  App.tk.HTTPC trace
  App.tk.HTTPC.wire trace
  App.tk.tkels trace
  App.tk.tkjwt trace
  App.tk.tcp info
  App.tk.eam debug
  App.tk.eam.rsa.pbe info
;;
run;

/* Use these log levels to set to default trace
  App.Grid.SGMG.Log trace
  App.Grid.SGMG.Log.Util.Lock info
  Audit.Authentication trace
  App.tk.http.server trace
  App.tk.HTTPC trace
  App.tk.HTTPC.wire trace
  App.tk.tkels trace
  App.tk.tkjwt trace
  App.tk.tcp info
  App.tk.eam debug
  App.tk.eam.rsa.pbe info
*/

/* Use these log levels to set back to normal
  App.Grid.SGMG.Log null
  App.Grid.SGMG.Log.Util.Lock null
  Audit.Authentication warn
  App.tk.http.server warn
  App.tk.HTTPC null
  App.tk.HTTPC.wire fatal
  App.tk.tkels null
  App.tk.tkjwt null
  App.tk.tcp null
  App.tk.eam null
  App.tk.eam.rsa.pbe null
*/

/* Initialize files to capture HTTP response body and headers. */

filename body temp;
filename headout temp;
filename input temp;
filename payload temp;

/* Build a PROC JSON of what we want from the loglevel datasets, writing it into the file "input". */

data _null_;
  file input;
    put 'proc json out=payload;';
    put 'write open object;';
    put 'write values "version" 1;';
    put 'write values "hosts";';
    put 'write open array;';
    put 'write close;';
run;

data _null_;
  file input mod;
  set work.loglevel nobs=last;
  if _n_=1 then do;
    put 'write values "loggers";';
    put 'write open array;';
  end;
  put 'write open object;';
  put 'write values "name" "' logger + (-1) '";';
  put 'write values "level" "' level + (-1) '";';
  put 'write close;';
  if _n_=last then do;
    put 'write close;';
    put 'write close;';
    put 'run;';
  end;
run;
/* Run the PROC JSON "input" file we just built. */
%include input;

/* Submit the logger update request JSON to the REST endpoint. */
/* If using SSPI remove the authorization = basic &auth header. */
proc http URL="&baseURL/sasgrid/api/loggers"
  method="PUT"
  in=payload
  headerout=headout
  headerout_overwrite
  ct="application/vnd.sas.sasgrid.loggers.request;version=1;charset=utf-8"
  clear_cache;
  headers "Accept"="*/*" "Authorization"="Basic &auth";
run;