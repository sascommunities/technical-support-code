/*******************************************************************************/
/* This program will extract from a directory of Metadata Server logs relavent */
/* authentication information and create a SAS data set of these values. These */
/* include the date and time of the authentication request, whether it was     */
/* accepted or rejected, the user and connection ID. The program will generate */
/* reports based on these connections.                                         */
/* Note: There are WINDOWS and LINUX specific paths/commands in use. Be sure   */
/* to comment out the commands you are not using.                              */
/*                                                                             */
/* Note: XCMD option is required for the directory listing function to operate.*/
/* Date: 28JUN2019                                                             */
/*******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Specify the path to the directory containing the log files to be parsed. */
%let path=C:\Path\To\MetaServerLogs;

/* Creating a file that is a directory listing of the supplied directory. */

/* Windows: */
filename DIRLIST pipe "dir /b /a-d &path"; 
/* Linux */
/*filename DIRLIST pipe "ls &path";*/
title;
proc datasets library=work nolist;
delete dirlist;
run;

/* Reading this list of files into a data set. */
data dirlist;
   infile dirlist lrecl=200 truncover;
   input file_name $100.;
run;

/* Creating a macro variable for the path to each log to be parsed, */
/*as well as the total number of log files. */

data _null_;
   set dirlist end=end;
   count+1;

   	call symputx('fn'||put(count,4.-l),file_name); 

/* Windows: */
	call symputx('read'||put(count,4.-l),cats("&path",'\',file_name)); 
/* Linux */
/*   call symputx('read'||put(count,4.-l),cats("&path",'/',file_name)); */


   if end then call symputx('max',count);
run;
%put;
%put NOTE: Found &max log files.;
%put;
/* This macro will for each file listed read in only authentication lines  */
/* There are commented out if statements to drop authentications from sasadm, sastrust, and sasevs users. */
%macro metaaudit; 

proc datasets library=work nolist;
     delete raw_import_open raw_import_closed raw_import_redirect redirects open_conn closed_conn opconbyhr clconbyhr conn_summary consum2 opencon2 raw_summary summary;
run;

%do i=1 %to &max;
%put;
%put NOTE: Reading log file &&fn&i;
%put;
data work.raw_import_open (keep=user status app date time hour timeInt connid) work.raw_import_closed (keep=user date time connid hour timeInt closed) work.raw_import_redirect (keep=date time hour timeInt host port);

/* Declare variables. */
	length datetimechar user $ 25 msg $ 500 status $ 8 app host $ 255 closed $ 1 port 8;
	format date date9. time time.;

/* Specify the file to read in from the macro variable. */
	
	infile "&&read&i" missover;
	input;
	rc=find(_INFILE_,'New client connection'); /* Only read in authentication lines. */
	if rc ge 1 then do;
			datetimechar=scan(_INFILE_,1," ");
			date=input(substr(datetimechar,1,10),yymmdd10.); /* Parse date. */
			time=input(substr(datetimechar,12,8),time8.); /* Parse time. */
			hour=hour(time);
			timeInt=floor(time/'00:10:00't);
			msg=substr(_INFILE_,rc); /* Store message string as a single variable. */
			/* The user name is in slightly different locations in the line depending on the connection type (trusted peer, token, IWA) */
			/* This part grabs the user from those various locations. */
				if scan(msg,11)="trusted" then user=scan(msg,15);
				else if scan(msg,12)="token" then user=scan(msg,14);
				else if scan(msg,11)="IWA" then user=scan(msg,13);
				else user=scan(msg,12); 
				user=lowcase(user);
			status=upcase(scan(msg,5)); /* Parse acceptance status. */
			connid=input(compress(scan(msg,4),"()"),8.); /* Parse connection ID. */
			pos=find(msg,'APPNAME=');
			if pos=0 then app=""; /* Set app variable as missing if we don't find APPNAME in the connection line. */
			else app=substr(msg,pos+8); /* Extract the client application. */
			/*if user in ("sasadm@saspw","sastrust@saspw","sasevs@saspw") then; else*/ output raw_import_open; /* Drop authentications from sastrust, sasadm and sasevs. */
		end;
	else do;
	    rc=prxmatch('/Client connection.*closed\./',_INFILE_);
		if rc ge 1 then do;
			datetimechar=scan(_INFILE_,1," ");
			date=input(substr(datetimechar,1,10),yymmdd10.); /* Parse date. */
			time=input(substr(datetimechar,12,8),time8.); /* Parse time. */
			hour=hour(time);
			timeInt=floor(time/'00:10:00't);
			closed="Y";
			msg=substr(_INFILE_,rc); /* Store message string as a single variable. */
			user=scan(msg,6);/* Read in user name. */
			user=lowcase(user);
			connid=scan(msg,3); /* Parse connection ID. */
			/*if user in ("sasadm@saspw","sastrust@saspw","sasevs@saspw") then; else*/ output raw_import_closed; /* Drop authentications from sastrust, sasadm and sasevs. */
		end;
		else do;
			rc=find(_INFILE_,'Redirect client in cluster'); /* Only read in authentication lines. */
			if rc ge 1 then do;
				datetimechar=scan(_INFILE_,1," ");
				date=input(substr(datetimechar,1,10),yymmdd10.); /* Parse date. */
				time=input(substr(datetimechar,12,8),time8.); /* Parse time. */
				hour=hour(time);
				timeInt=floor(time/'00:10:00't);
				msg=substr(_INFILE_,rc); /* Store message string as a single variable. */
				host=scan(scan(msg,-1," "),1,":");
				port=input(compress(scan(scan(msg,-1," "),2,":"),"."),5.);
				output raw_import_redirect;
			end;
		end;
	end;
run;

/* Put counts for different connection types into macro variables */
proc sql noprint;
	select count(connid) into:accepted from work.raw_import_open where status="ACCEPTED";
	select count(connid) into:rejected from work.raw_import_open where status="REJECTED";
	select count(connid) into:closed from work.raw_import_closed;
	select count(host) into:redirects from work.raw_import_redirect;
quit;

/* Write these values to the SAS log. */
%put;
%put NOTE: &accepted connections accepted.;
%put NOTE: &rejected connections rejected.;
%put NOTE: &closed connections closed.;
%put NOTE: &redirects connections redirected.;
%put;

/* Create a summary dataset. */
data raw_summary;
	length log $ 255 accepted rejected opened closed 8;
	log="&&fn&i";
	accepted=&accepted;
	rejected=&rejected;
	opened=accepted+rejected;
	closed=&closed;
	delta=opened-closed;
	redirects=&redirects;
	noredirect=(accepted-redirects);
run;

proc append base=work.redirects data=raw_import_redirect; run;
proc append base=work.summary data=raw_summary; run;
proc append base=work.open_conn data=raw_import_open; run; /* Append the dataset into the master data set for all logs. */
proc append base=work.closed_conn data=raw_import_closed; run;


%end;

%mend;

/* Run the macro. */
%metaaudit; 

/* Report Generation */

proc print data=summary;
title "Summary of Logs and Connections";
run;

proc means data=work.open_conn(where=(status="ACCEPTED")) max nonobs noprint;
	class user;
	var date;
	output out=work.lastlog max=date;
run;

PROC SQL noprint;
	create view opconbyhr as select hour, count(hour) as opened from open_conn group by hour; 
	create view clconbyhr as select hour, count(hour) as closed from closed_conn group by hour; 
	create view conn_summary as select opconbyhr.hour,opened,closed,(opened-closed) as delta from opconbyhr,clconbyhr where opconbyhr.hour=clconbyhr.hour;
	create view consum2 as select open_conn.date,open_conn.time,app,open_conn.connid,closed from open_conn LEFT OUTER JOIN closed_conn on open_conn.connid=closed_conn.connid;
	create view opencon2 as select app, count(connid) as count from consum2 where closed IS NULL group by app; /* Find any connections left open. */
	create view redir_summary as select date, host, count(hour) as redirects from redirects group by date,host;
	create view work.lastlogin as select * from work.lastlog where _TYPE_ = 1;
quit;

title "Unclosed Connections by Application for Log Range";

PROC REPORT data=opencon2;
columns app count;
define app/group;
rbreak after/summarize style=Header;
compute after;
app= 'Total';
endcomp;
RUN;

title "Connections Opened for Log Range by Application";

PROC REPORT data=open_conn;
	columns app n;
	define app/group;
	define n / 'Connections';
	rbreak after/summarize style=Header;
	compute after;
		app= 'Total';
	endcomp;
RUN;

title "Connections Opened and Closed by Hour";

PROC REPORT data=conn_summary;
	columns hour opened closed delta;
	define hour/group;
	rbreak after/summarize style=Header;
	compute after;
	endcomp;
RUN;

title "Redirects by Date by Host";

PROC REPORT data=redir_summary;
columns date host redirects;
define date/order;
rbreak after/summarize style=Header;
compute after;
host= 'Total';
endcomp;
RUN;

title "Most Recent Login Date by User";
proc print data=work.lastlogin noobs; var user date; run;