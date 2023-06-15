/******************************************************************************/
/* This program will run bhist -T to get a list of jobs in a given range      */
/* (i.e. from 1 week ago to today) then will run bhist -l <job_id> against    */
/* each one and parse the output into a data set. This can produce a lot of   */
/* lines if you have a lot of jobs.                                           */
/* As the program uses a filename PIPE to run commands, it requires XCMD      */
/* to be set.                                                                 */
/* Date: 25MAR2021                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Create a table of job ids submitted within the supplied range. */

filename command pipe 'bhist -t -T "$(date -d "1 week ago" +%Y/%m/%d/%H:%M),$(date +%Y/%m/%d/%H:%M)" | grep Job.*submitted -o | cut -f2 -d" "';

data jobs;
	length jobid 8;
	infile command;
	input;
	jobid = compress(_infile_,"<>");
	put jobid;
run;

/* Create an empty destination table. */

data jobinfo;
	length Job $ 10 User $ 50 Project $ 50 Command $ 255 max_mem avg_mem $ 20 pend psusp run ususp ssusp unknwn total 8;
	call missing (of _all_);
	stop;
run;

/* Define a macro to read in bhist output for a supplied job and add it to the table. */

%macro bhistreader(job_id=);

/* Define the bhist command. */
filename bhist;
filename bhist pipe "bhist -l &job_id";

/* Create a temp file to store the edited output. */
filename bhist2;
filename bhist2 temp;

/* Remove formatting from command output and store it in the temp file. */
data _null_;
	infile bhist;
	file bhist2;
	input;
	if  _infile_ ne: "                     " and _N_ > 1 then put ;
	line=strip(_infile_);
	put line +(-1) @@ ;	
run;

/* Create a data set, jobinf, to store the history information from our unformatted file. */
data jobinf;
	length Job $ 10 User $ 50 Project $ 50 Command $ 255 ;
	call missing (of _character_);
	infile bhist2 dlm=',';
	input @'Job' Job  @'User' User @'Project' Project @'Command' Command;
	Job=compress(Job,"<>");
	User=compress(User,"<>");
	Project=compress(Project,"<>");
	Command=compress(Command,"<>");
run;

/* Extract memory usage information from the output, only reading the memory line. */
data meminfo;
length line $ 512 max_mem avg_mem $ 20;
infile bhist2;
input;
line=strip(_infile_);
if scan(line,1)="MAX" then do;
	max_mem=cat(scan(line,3),scan(line,4));
	avg_mem=cat(scan(line,7),scan(line,8));
	output;
end;
drop line;
run;
/* Read in the table of state times from the output. */
data times;
	length line $ 512 pend psusp run ususp ssusp unknwn total 8;
	infile bhist2;
	input @;
	line=strip(_infile_);
	prefix=scan(line,1);
	put prefix=;
	if prefix="PEND" then do;
		input;
		input pend psusp run ususp ssusp unknwn total;
		output;
	end;
	drop line prefix;
run;

proc sql;
insert into work.jobinfo 
select * from jobinf,meminfo,times;
quit;

%mend;

/* Run the macro for each job in the job table. */

data _null_ ;
	set jobs;
	str=catt('%bhistreader(job_id=',jobid,');');
	call execute(str);
run;

proc print data=jobinfo; run;