/* iom_log_parser.sas */
/* This program is designed to read common log lines from IOM server log files (Metadata Server, Object Spawner) */
/* and capture into SAS datasets information for further analysis. */
/* The program defines a macro, logparser, to generate the datasets and runs some commonly desired reports from those datasets. */
/* The macro will produce the following datasets: */
/* import_open - New client connections and out call connections */
/* import_closed - Client connections closed  */
/* import_redirectlb - When a client was redirected through load balancing */
/* import_jobs - Created grid jobs */
/* import_redirwkspc - When a client was redirected to a server */
/* import_run - Spawned process created */
/* import_end - Spawned process ended */
/* import_warn - Warnings  */
/* import_err - Errors */
/* import_auditobj - Audit Public Object records */
/* import_auditchg - Added/Removed Member records */
/* delays - A table with calculated delays in getting a requested server */
/* griddelays - A table with calculated delays in getting a grid job and getting a requested server */
/* connections - A table of connections and whether they were closed, how long they were open. */
/* rundur - A table calculating run duration of servers */
/* summary - Summary of the log file, including counts of connections opened, closed, and redirected */

/* After the macro runs, the code produces a number of reports and graphs depending on the avaialble input. */
/* Those reports are: */
/* A summary of warnings */
/* A summary of errors */
/* A summary of connections opened, closed, and redirected from each log file */
/* The last login time of each user */
/* Unclosed connections by application */
/* All connections by application */
/* Group membership changes */
/* Public object changes */
/* Graph of grid delays over time */
/* Graph of server delays over time */
/* Table of job requests / server requests by hour */
/* Table of job requests / server requests by defined interval */

/* Date: 07MAY2025 */

/* Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Define the log directory to read in. */
%let logdir = /path/to/logs;

/* Define a datetime interval format to use for interval based reporting (e.g. dtminute15) */
%let intervalformat = 'dtminute15';

/* Begin macro definition */
%macro logparser(logdir);

    /* PROC DATASETS - Delete any preexisting WORK datasets from previous analysis */
    proc datasets library=work nolist;
    delete
        import_open
        import_closed
        import_redirectlb
        import_jobs
        import_redirwkspc
        import_run
        import_end
        import_warn
        import_err
        import_auditobj
        import_auditchg
        delays
        griddelays
        connections
        rundur
        summary;
    quit;

    /* DATA Step - Create empty tables to populate with data while reading the log files. */
    data 
        import_open (keep=user datetime threadid msg status connid app file exhost expid) 
        import_closed (keep=user datetime threadid msg closed connid file exhost expid) 
        import_redirectlb (keep=datetime threadid msg host port file) 
        import_jobs (keep=datetime threadid msg jobid file) 
        import_redirwkspc (keep=datetime threadid msg host port file)
        import_run (keep=datetime threadid msg jobid pid cid file)
        import_end (keep=datetime threadid msg jobid pid cid file user)
        import_warn (keep=datetime threadid msg file)
        import_err (keep=datetime threadid msg file)
        import_auditobj (keep=datetime threadid user name objid action type)
        import_auditchg (keep=datetime threadid user memname memobjid tarname tarobjid action type)
        ;

        /* Don't create any observations. */
        stop;   

        /* Initialize variables. */
        length
            datetime 8
            level $ 5
            user $ 255
            jobid 8
            threadid $ 8
            msg $ 512
            host $ 512
            port 8
            closed $ 1
            status $ 10
            connid 8
            name
            memname
            tarname
            memobjid
            tarobjid
            objid $ 17
            action
            type $ 25
            app $ 100
            file $ 512
            pid cid 8
            exhost $ 256
            expid 8
            ;

        label
            datetime = "Timestamp"
            level = "Level"
            user = "User"
            jobid = "Job ID"
            threadid = "Thread ID"
            msg = "Message"
            host = "Host"
            port = "Port"
            closed = "Closed"
            status = "Status"
            connid = "Connection ID"
            name = "Name"
            memname = "Member Name"
            tarname = "Target Name"
            memobjid = "Member Object ID"
            tarobjid = "Target Object ID"
            objid = "Object ID"
            action = "Action"
            type = "Type"
            app = "Application"
            file = "File"
            pid = "Process ID"
            cid = "Child ID"
            exhost = "Execution Host"
            expid = "Execution PID"
            ;


        call missing (of _character_);
        
        format 
            datetime datetime.
            ;
    run;

    /* Build a summary dataset */
    data summary;
        length log $ 255 accepted rejected opened closed delta redirects noredirect 8;
        stop;
    run;

    /* Create a logpath fileref pointing to the log directory. */
    %let rc=%sysfunc(filename(path,&logdir));

    /* Open the directory using the DOPEN function. */
    %let did=%sysfunc(dopen(&path));

    /* Only proceed if we successfully opened the directory. */
    %if &did ne 0 %then %do;

        /* Count the members of the directory. */
        %let memcnt=%sysfunc(dnum(&did));

        /* Loop through each member. */
        %do i=1 %to &memcnt;

            /* Define a macro variable filenm that is the name of the file. */
            %let filenm=%qsysfunc(dread(&did,&i));

            /* Set the full path to a fileref. */
            filename logfile "&logdir/&filenm";

            /* Open the file using the FOPEN function. */
            %let fid=%sysfunc(fopen(logfile));

            /* Only proceed if we successfully opened the file. */
            %if &fid ne 0 %then %do;

                /* PROC DATASETS - Delete any existing raw_import tables in the WORK library from previous runs of the loop or macro. */
                proc datasets library=work nolist;
                delete 
                    raw_import_open
                    raw_import_closed
                    raw_import_redirectlb
                    raw_import_jobs
                    raw_import_redirwkspc
                    raw_import_run
                    raw_import_end
                    raw_import_warn
                    raw_import_err
                    raw_import_auditobj
                    raw_import_auditchg
                    raw_summary
                    ;
                quit;

                /* DATA Step - Read the log file line by line and parse the lines into the appropriate dataset. */
                data 
                    raw_import_open (keep=user datetime threadid msg status connid app file exhost expid) 
                    raw_import_closed (keep=user datetime threadid msg closed connid file exhost expid) 
                    raw_import_redirectlb (keep=datetime threadid msg host port file) 
                    raw_import_jobs (keep=datetime threadid msg jobid file) 
                    raw_import_redirwkspc (keep=datetime threadid msg host port file)
                    raw_import_run (keep=datetime threadid msg jobid pid cid file)
                    raw_import_end (keep=datetime threadid msg jobid pid cid file user)
                    raw_import_warn (keep=datetime threadid msg file)
                    raw_import_err (keep=datetime threadid msg file)
                    raw_import_auditobj (keep=datetime threadid user name objid action type)
                    raw_import_auditchg (keep=datetime threadid user memname memobjid tarname tarobjid action type)
                    ;

                    /* Initialize variables. */
                    length
                        datetime 8
                        level $ 5
                        user $ 255
                        jobid 8
                        threadid $ 8
                        msg $ 512
                        host $ 512
                        port 8
                        closed $ 1
                        status $ 10
                        connid 8
                        name
                        memname
                        tarname
                        memobjid
                        tarobjid
                        objid $ 17
                        action
                        type $ 25
                        app $ 100
                        file $ 512
                        pid cid 8
                        exhost $ 256
                        expid 8
                        ;
                    

                    call missing (of _character_);
                    format 
                        datetime datetime.
                        ;

                    /* Read in the file. */
                    infile logfile missover;
                    input;

                    /* Define the variable "file" as the file name. */
                    file="&filenm";

                    /* If the files haven't been renamed, we can pull the execution host and PID from them. */
                    %let pid=%scan(%scan(&filenm,-1,"_"),1,".");
                    %let host=%scan(&filenm,-2,"_");

                    /* If line doesn't start with a date stamp, skip it. */
                    /* This should follow the format ####-##-##T##:##:##,### */
                    rc=prxmatch('/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/',_INFILE_);

                    /* The PRXMATCH function returns the position of the first match of the regular expression in the string. */
                    if rc ne 1 then delete;

                    /* Grab values relevant to all lines (datetime, level, thread, message, execution host and execution PID) */
                    datetime=input(scan(_INFILE_,1," "),ymddttm.);
                    level=scan(_INFILE_,2," ");
                    threadid=compress(scan(_INFILE_,3," "),"[]");
                    msg=substr(_INFILE_,find(_INFILE_,scan(_INFILE_,6," ")));
                    exhost="&host";
                    expid=&pid;

                    /* Capture warnings and errors to their datasets  */
                    if level eq "WARN" then do;
                            output raw_import_warn;
                    end;
                    else do;
                        if level eq "ERROR" then do;
                            output raw_import_err;
                        end;
                    end;

                    /* This next part uses a series of nested IF statements to figure out the type of message we are reading, */
                    /* read in the relevant data points from that message, and output it to the appropriate data set.  */

                    /* See if the line we are reading is a new connection line. */
                    rc=find(msg,'New client connection');

                    /* If so, capture stuff from the line into variables in the "raw_import_open" dataset. */
                    /* if not, we have a series of nested "else" statements to check for other key words in the lines. */
                    if rc ge 1 then do;
                            user=compress(scan(_infile_,4," "),":"); /* Read in user name. */
                            status=upcase(scan(msg,5)); /* Parse acceptance status (accepted or rejected), converting to uppercase. */
                            connid=input(compress(scan(msg,4),"()"),8.); /* Parse connection ID. */
                            pos=find(msg,'APPNAME='); /* This finds the APPNAME part of the message if it's there, meaning the client identified itself */
                            if pos=0 then app=""; /* Set app variable as missing if we don't find APPNAME in the connection line. */
                            else app=substr(msg,pos+8); /* Extract the client application. */
                            /* Remove the trailing period from the APPNAME. */
                            p=findc(app,".","K",-length(app));
                            if p then app=substr(app,1,p);
                            /* Drop authentications from sastrust, sasadm and sasevs to save space. You can comment out from "if" to "else" to include these. */
                            /* if user in ("sasadm@saspw","sastrust@saspw","sasevs@saspw") then; else */ output raw_import_open; 
                    end;
                    else do;
                        /* See if the line we are reading is a closing connection. */
                        rc=prxmatch('/Client connection.*closed\./',msg);

                        /* if so, read its line into variables in the raw_import_closed dataset */
                        if rc ge 1 then do;
                            closed="Y"; 
                            user=scan(msg,6);/* Read in user name. */
                            connid=input(scan(msg,3),8.); /* Parse connection ID. */
                            /* Drop authentications from sastrust, sasadm and sasevs to save space, comment out from "if" to "else" to include them. */
                            /* if user in ("sasadm@saspw","sastrust@saspw","sasevs@saspw") then; else */ output raw_import_closed; 
                        end;
                        else do;
                            /* See if the line we are reading is a redirect (load-balancing) client line. */
                            rc=find(msg,'Redirect client in cluster'); 

                            /* If so, read the line details into the raw_import_redirectlb dataset. */
                            if rc ge 1 then do;
                                host=scan(scan(msg,-1," "),1,":");
                                port=input(compress(scan(scan(msg,-1," "),2,":"),"."),5.);
                                output raw_import_redirectlb;
                            end;

                            /* Metadata Server specific tests */

                            else do;
                                /* See if we the line we are reading is a metadata public object audit message. */
                                rc=find(_INFILE_,'Audit Public Object'); 

                                /* If so, read the line details into the raw_import_auditobj dataset. */
                                if rc ge 1 then do;
                                            user=scan(scan(_infile_,4," "),2,":");
                                            namepos=find(msg,'Name=');
                                            objidpos=find(msg,'ObjId=');
                                            typelen=namepos - 26;
                                            type=substr(msg,26,typelen);
                                            objid=substr(msg,objidpos+6,17);
                                            name=substr(msg,namepos+5,objidpos-namepos-5);
                                            action=upcase(compress(scan(msg,-1," "),"."));
                                            output raw_import_auditobj;
                                end;
                                else do;
                                    /* See if we the line we are reading is a metadata membership change audit message. */
                                    rc=prxmatch('/(Added|Removed) Member/',_INFILE_); 

                                    /* If so, read the line details into the raw_import_auditchg dataset. */
                                    if rc ge 1 then do;
                                        user=scan(scan(_infile_,4," "),2,":");
                                        action=upcase(cat(scan(msg,1," ")," ","member"));
                                        memnamepos=find(msg,'Name=');
                                        memobjidpos=find(msg,'ObjId=');
                                        tarnamepos=find(msg,'Name=',-1*length(msg));
                                        tarobjidpos=find(msg,'ObjId=',-1*length(msg));
                                        type=scan(scan(msg,3," "),2,"=");
                                        memobjid=substr(msg,memobjidpos+6,17);
                                        memname=compress(substr(msg,memnamepos+5,memobjidpos-memnamepos-5),",");
                                        tarobjid=substr(msg,tarobjidpos+6,17);;
                                        tarname=compress(substr(msg,tarnamepos+5,tarobjidpos-tarnamepos-5),",");
                                        output raw_import_auditchg;
                                    end;

                                    /* End Metadata Server specific tests */

                                    /* Object Spawner specific tests */
                                    else do;
                                        /* See if the line is a created grid job line. */
                                        rc=find(msg,'Created grid job'); 

                                        /* If so, grab info into the raw_import_jobs dataset. */
                                        if rc ge 1 then do;
                                            jobid=input(scan(msg,4," "),8.);
                                            output raw_import_jobs;
                                        end;
                                        else do;
                                            /* See if the line is a peer redirection line (sending the client to the workspace server after it has started.) */
                                            rc=find(msg,'Redirecting peer'); 

                                            /* If so, pull the info into variables in the raw_import_redirwkspc dataset. */
                                            if rc ge 1 then do;
                                                host=scan(msg,6," ");
                                                port=input(compress(scan(msg,-1," "),"."),5.);
                                                output raw_import_redirwkspc;
                                            end;
                                            else do;
                                                /* See if the line is a process started line. */
                                                rc=prxmatch('/(Created|Launched).process/',msg);
                                                if rc ge 1 then do;
                                                /* Lines are different for a grid versus non-grid job. */
                                                /* Created process <pid> using credentials sasdemo (child id ##). */
                                                /* Launched process <jobid> (child id ##) is now running as process <pid>. */
                                                /* Test if this was a grid job. */
                                                    rc=find(msg,'Launched process');
                                                    if rc ge 1 then do;
                                                        jobid=input(scan(msg,3," "),8.);
                                                        cid=input(compress(scan(msg,6," "),")"),8.);
                                                        pid=input(compress(scan(msg,12," "),"."),8.);
                                                        output raw_import_run;
                                                    end;
                                                    else do;
                                                        jobid=.;
                                                        cid=input(compress(scan(msg,9," "),")"),8.);
                                                        pid=input(compress(scan(msg,3," "),"."),8.);
                                                        output raw_import_run;
                                                    end;
                                                end;
                                                else do;
                                                    /* See if the line is a process ended line. */
                                                    rc=prxmatch('/Process.*has ended\./',msg);
                                                    if rc ge 1 then do;
                                                        pid=input(scan(msg,2),8.);
                                                        /* Lines are different for a grid versus non-grid job. */
                                                        /* Process ### (originally grid job ###) for user sasdemo (child id ##) has ended. */
                                                        /* Process 0 (originally 4064032) for user sassrv (child id 887) has ended. */
                                                        /* Process ### owned by user sassrv (child id ##) has ended. */
                                                        /* Test if this was a grid job. */

                                                        if scan(msg,4)="grid" then do;
                                                            /* Read in the job ID, removing the trailing ")" */
                                                            jobid=input(compress(scan(msg,6," "),")"),8.);
                                                            /* Read in the child ID, removing the trailing ")" */
                                                            cid=input(compress(scan(msg,12," "),")"),8.);
                                                            /* Read in the user name  */ 
                                                            user=scan(msg,9," ");
                                                        end;
                                                        /* Need to tolerate the change in PID format. */
                                                        else if compress(scan(msg,3," "),"(")="originally" then do;
                                                            jobid=.;
                                                            cid=input(compress(scan(msg,10," "),")"),8.);
                                                            user=scan(msg,7," ");
                                                        end;
                                                        else do;
                                                            jobid=.;
                                                            cid=input(compress(scan(msg,9," "),")"),8.);
                                                            user=scan(msg,6," ");
                                                        end;
                                                        
                                                        output raw_import_end;
                                                    end;
                                                    else do;
                                                        /* Capture outbound connections. */
                                                        rc=find(msg,'New out call client connection');
                                                        if rc ge 1 then do;
                                                                user=compress(scan(_infile_,4," "),":"); /* Read in user name. */
                                                                status='ACCEPTED'; 
                                                                connid=input(compress(scan(msg,6),"()"),8.); /* Parse connection ID. */
                                                                app=""; 
                                                                /* Drop authentications from sastrust, sasadm and sasevs to save space. You can comment out from "if" to "else" to include these. */
                                                                /* if user in ("sasadm@saspw","sastrust@saspw","sasevs@saspw") then; else */ output raw_import_open; 
                                                        end;
                                                    end;

                                                    /* End Object Spawner specific tests */

                                                end;
                                            end;
                                        end;
                                    end;
                                end;
                            end;
                        end;
                    end;
                run;

                /* Close the file. */
                %let rc=%sysfunc(fclose(&fid));

                /* PROC SORT - Sort all of the raw data sets by timestamp. */
                proc sort data=raw_import_open;
                   by datetime;
                run;
                proc sort data=raw_import_closed;
                    by datetime;
                run;
                proc sort data=raw_import_jobs;
                    by datetime;
                run;
                proc sort data=raw_import_redirectlb;
                    by datetime;
                run;
                proc sort data=raw_import_redirwkspc;
                    by datetime;
                run;
                proc sort data=raw_import_run;
                    by datetime;
                run;
                proc sort data=raw_import_end;
                    by datetime;
                run;
                proc sort data=raw_import_warn;
                    by datetime;
                run;
                proc sort data=raw_import_err;
                    by datetime;
                run;
                proc sort data=raw_import_auditobj;
                    by datetime;
                run;
                proc sort data=raw_import_auditchg;
                    by datetime;
                run;

                /* Put counts for different connection types into macro variables */
                proc sql noprint;
                    select count(connid) into:accepted from work.raw_import_open where status="ACCEPTED";
                    select count(connid) into:rejected from work.raw_import_open where status="REJECTED";
                    select count(connid) into:closed from work.raw_import_closed;
                    select count(host) into:redirects from work.raw_import_redirectlb;
                quit;

                /* Write these values to the SAS log. */
                %put;
                %put NOTE: For file &filenm;
                %put NOTE: &accepted connections accepted.;
                %put NOTE: &rejected connections rejected.;
                %put NOTE: &closed connections closed.;
                %put NOTE: &redirects connections redirected.;
                %put;

                /* Build a summary dataset */
                data raw_summary;
                    length log $ 255 accepted rejected opened closed delta redirects noredirect 8;
                    log="&filenm";
                    accepted=&accepted;
                    rejected=&rejected;
                    opened=accepted+rejected;
                    closed=&closed;
                    delta=opened-closed;
                    redirects=&redirects;
                    noredirect=(accepted-redirects);
                run;

                /* Since these datasets will be overwritten with each file, we need to persist over multiple iterations. */
                proc sql;
                    insert into import_open select * from raw_import_open;
                    insert into import_closed select * from raw_import_closed;
                    insert into import_redirectlb select * from raw_import_redirectlb;
                    insert into import_jobs select * from raw_import_jobs;
                    insert into import_redirwkspc select * from raw_import_redirwkspc;
                    insert into import_run select * from raw_import_run;
                    insert into import_end select * from raw_import_end;
                    insert into import_warn select * from raw_import_warn;
                    insert into import_err select * from raw_import_err;
                    insert into import_auditobj select * from raw_import_auditobj;
                    insert into import_auditchg select * from raw_import_auditchg;
                    insert into summary select * from raw_summary;
                quit;

            %end; /* End the do if we could open the file. */
            %else %do;
                /* If we couldn't open the file, write a message to the log. */
                %put WARN: Could not open file &filenm.;
            %end; 
        %end; /* End the do loop for each file in the directory. */

        /* Close the directory. */
        %let rc=%sysfunc(dclose(&did));

    %end; /* End the if we could open the directory. */
    %else %do;
        /* If we couldn't open the directory, write a message to the log. */
        %put WARN: Could not open directory &logdir.;
    %end;

    /*** LAST LOGIN ***/
    /* Calculate last login */
    proc means data=import_open(where=(status="ACCEPTED")) max nonobs noprint mode nway;
        class user;
        var datetime;
        output out=lastlogin (drop =_:) max=datetime;
    run;

    /* Sort it. */
    proc sort data=lastlogin;
        by datetime;
    run;

    /* PROC SQL - Build analysis tables */
    proc sql;
        /*** GRID DELAYS ***/
        /* This table captures the delay between when a grid job request arrived and when we got a job ID. */
            /* Delays here suggest either the object spawner was delayed in submitting the request to grid, */
            /* or the grid server was delayed in responding to our request. */
        /* It also tracks how long after we got the job ID that we redirected to the running server. */
            /* Delays here suggest that either the object spawner was delayed in responding to the server advising it was ready, */
            /* or the server was delayed in notfiying the object spawner. */
        create table griddelays as
        select
            a.datetime as reqdt label="Initial Request DT",
            b.datetime as jobdt label="Job ID Create DT",
            c.datetime as redirdt label="Client Redirect DT",
            (jobdt - reqdt) as jobdelay label="Job ID Delay (s)", /* How long after the server was requested did we get a job ID back? */
            (redirdt - jobdt) as redirdelay label="Client Redirect Delay (s)", /* How long after we got the job ID did the server start and be issued a port bank port  */
            a.user as user,
            a.threadid as thread,
            a.file as file
        from
            import_open as a,
            import_jobs as b,
            import_redirwkspc as c
        where
            a.threadid = b.threadid and
            b.threadid = c.threadid and
            a.file = b.file and
            b.file = c.file;

        /*** DELAYS ***/
        /* This table omits the grid component for non-grid environments, just tracking how long after the object spawner received */
        /* a request for a server that it redirected the client to the server. */
            /* Delays here suggest either the object spawner was delayed in starting the server, */
            /* the launched server was delayed in advising it was ready, or the object spawner was delayed in responding to that advise. */
        create table delays as
        select
            a.datetime as reqdt label="Initial Request DT",
            b.datetime as redirdt label="Client Redirect DT",
            (redirdt - reqdt) as redirdelay label="Client Redirect Delay (s)", /* How long after the request did the server start and be issued a port bank port  */
            a.user as user,
            a.threadid as thread,
            a.file as file
        from
            import_open as a,
            import_redirwkspc as b
        where
            a.threadid = b.threadid and
            a.file = b.file;
        
        /*** CONNECTIONS ***/
        /* This table captures the time between when a connection was opened and when it was closed. */
            /* This is useful for tracking how long connections are open, and if they are being closed properly. */
        create table connections as
        select
            a.datetime as opendt label="Initial Connection DT",
            b.datetime as closedt label="Connection Close DT",
            (closedt-opendt) as openduration label="Connection Open Duration (s)",
            a.user as user,
            a.app as app,
            a.connid as connid label="Connection ID",
            b.closed as closed,
            a.file as file
        from
            import_open as a left join
            import_closed as b
        on a.connid = b.connid and a.exhost = b.exhost and a.expid = b.expid;

        /*** RUN DURATIONS ***/
        /* For processes where we have a start and end, create a table of how long they ran. */
        create table rundur as
        select
            a.datetime as startdt label="Process start dt",
            b.datetime as enddt label="Process end dt",
            (enddt-startdt) as runduration label="Process run duration (s)",
            b.user,
            a.file as file
        from
            import_run as a,
            import_end as b
        where
            a.jobid = b.jobid and
            a.cid = b.cid and
            a.pid = b.pid and
            a.file = b.file;
    quit;

    /* Sort the new tables */

    proc sort data=connections; by opendt; run;
    proc sort data=griddelays; by reqdt; run;
    proc sort data=delays; by reqdt; run;
    proc sort data=rundur; by startdt; run;

%mend logparser;
/* End of macro definition */

/* Call the macro to run it. */
/* You can specify the log directory here. */
%logparser(logdir=&logdir);

/* Now we have the tables we can provide some reporting from them. */

/* Clear any existing titles. */
title; title2;

/* Common Reporting */
title "IOM Log Analysis";

/* Report on frequency of the Warnings and Errors */
title2 "Frequency of Warnings";
proc freq data=import_warn;
    table file msg / nopercent nocum;
run;
title2 "Frequency of Errors";
proc freq data=import_err;
    table file msg / nopercent nocum;
run;

/* Connection Summary */
proc print data=summary;
title2 "Summary of Logs and Connections";
run;

/* Most Recent Login Date by User */
title2 "Most Recent Login Date by User";
proc print data=work.lastlogin noobs; var user datetime; run;

/* Unclosed Connections by Application */
title2 "Unclosed Connections by Application";
proc report data=connections(where=(closed is null));
    columns app n;
    define app/group;
    define n / 'Connections';
    rbreak after/summarize style=Header;
    compute after;
    app= 'Total';
    endcomp;
run;

/* All Connections by Application */
title2 "All Connections by Application";
proc report data=connections;
    columns app n;
    define app/group;
    define n / 'Connections';
    rbreak after/summarize style=Header;
    compute after;
    app= 'Total';
    endcomp;
run;

/* Metadata Specific Reports */
title "IOM Log Analysis - Metadata Server";

/* Group Membership Changes */
title2 "Group Membership Changes";
proc report data=work.import_auditchg ; 
columns datetime user action type memname tarname ; 
define datetime/order;
run;

/* Object Changes */
title2 "Public Object Changes";
proc report data=work.import_auditobj ; 
columns datetime user action type name objid ; 
define datetime/order;
run;

/* Object Spawner Specific Reports */
title "IOM Log Analysis - Object Spawner";

/* Graph the history on Grid delays. */
proc sgplot data=griddelays;
    title2 "Delays in Launching and Redirecting Grid Jobs";
    series x=reqdt y=jobdelay;
    series x=jobdt y=redirdelay;
    xaxis label="Start time";
    yaxis label="Delay (s)";
run;

/* Graph history on all delays */
title2 "Delays in Launching and Redirecting Jobs";
proc sgplot data=delays;
    series x=reqdt y=redirdelay;
    xaxis label="Request time";
    yaxis label="Delay (s)";
run;

/* Job Requests Per Hour */
proc sql;
    create view jobsperhr as
    select intnx('hour',datetime,0,'B') format=datetime. as hour format=datetime. as hour from import_jobs;
quit;
title2 "Jobs per Hour";
proc freq data=jobsperhr;
run;

/* Server requests per hour */
proc sql;
    create view jobsperhr as
    select intnx('hour',reqdt,0,'B') format=datetime. as hour format=datetime. as hour from delays;
quit;
title2 "Server Requests per Hour";
proc freq data=jobsperhr;
run;

/* Job Requests Per Interval */
proc sql;
    create view jobsperint as
    select intnx(&intervalformat,datetime,0,'B') format=datetime. as hour format=datetime. as hour from import_jobs;
quit;
title2 "Jobs per Interval";
proc freq data=jobsperint;
run;

/* Server Requests Per Interval */
proc sql;
    create view jobsperint as
    select intnx(&intervalformat,reqdt,0,'B') format=datetime. as hour format=datetime. as hour from delays;
quit;
title2 "Server Requests per Interval";
proc freq data=jobsperint;
run;

/* Clear titles. */
title; title2;