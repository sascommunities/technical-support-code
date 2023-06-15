/******************************************************************************/
/* This program will get the idle time of all running workspace servers and   */
/* optionally tell the object spawner to stop any whose idle time exceeds a  */
/* given timeout value.                                                       */
/* Date: 03OCT2022                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Metadata connection information: */

%let metaserve=meta.demo.sas.com;
%let metaport=8561;
%let userid=sasadm@saspw;
%let pass=password;

/* Add killing function. */
/* Timeout is in seconds, so 3600 is 1 hour */
%let timeout=3600;
/* If kill is anything other than yes, the stop server command should not occur */
%let kill=yes;
/* End edit. */

/* Connect to Metadata Server */

options	metaserver="&metaserve"
		metaport=&metaport
		metauser="&userid"
		metapass="&pass"
		metarepository=Foundation
		metaprotocol=BRIDGE;

data work.objspawn;

	keep host_name port; /* Only keep hosts and port for Object Spawners. */
	retain port; /* Keep port for all iterations. */

	/* Declare and initialize variables. */

	length type id objspwn_uri tree_uri mach_uri host_name conn_uri port $ 50;
	call missing(of _character_);

	/* This is the XML Select query to locate Object Spawners. */
	obj="omsobj:ServerComponent?@PublicType='Spawner.IOM'";

	/* Test for definition of Object Spawner(s) in Metadata. */

	objspwn_cnt=metadata_resolve(obj,type,id);
	if objspwn_cnt > 0 then do n=1 to objspwn_cnt;

	/* Get URI for each Object Spawner found. */

		rc=metadata_getnobj(obj,n,objspwn_uri);

		/* Get associated attributes for the object spawner (connection port and hosts) */

		rc=metadata_getnasn(objspwn_uri,"SoftwareTrees",1,tree_uri);
		rc=metadata_getnasn(objspwn_uri,"SourceConnections",1,conn_uri);
		rc=metadata_getattr(conn_uri,"Port",port);
		mach_cnt=metadata_getnasn(tree_uri,"Members",1,mach_uri); 

		/* For each host found, get the host name and output it along with the port number to the dataset. */

		do m=1 to mach_cnt;
			rc=metadata_getnasn(tree_uri,"Members",m,mach_uri);
			rc=metadata_getattr(mach_uri,"Name",host_name);
			output;
		end;
	end;
	else put "No Object Spawners defined in Metadata.";	
run;

/* WORK.OBJSPAWN now contains a list of hosts running Object Spawners. */

/* Macro below will query each host for the Workspace Servers it has spawned. */

%macro getwkspc;

/* Count how many Object Spawners are defined in WORK.OBJSPAWN as a Macro variable. */

proc sql noprint;
	select count(*) into :nobjs from work.objspawn;
quit;

%if &nobjs > 0 %then %do; /* If hosts were found, extract them as macro variables. */

proc sql noprint;
	select host_name into:host1-:host%left(&nobjs) from work.objspawn;
	select port into:port1-:port%left(&nobjs) from work.objspawn;
quit;

%end;
%else;

/* Create base tables. */
data work.wkspc;
length SERVERCOMPONENT LOGICALNAME $50 SERVERCLASS PROCESSOWNER SERVERID $36;
call missing(of _character_);
	if compress(cats(of _all_),'.')=' ' then delete;
run;
data work.wkspcidle;
length SERVERCOMPONENT LOGICALNAME $50 SERVERCLASS PROCESSOWNER SERVERID $36 CATEGORY NAME $ 1024 VALUE $ 4096;
call missing(of _character_);
	if compress(cats(of _all_),'.')=' ' then delete;
run;

/* Connect to each object spawner to get the workspace servers it has spawned, output them to a dataset. */

%do i=1 %to &nobjs;
	proc iomoperate;
		connect host="&&host&i"
				port=&&port&i
				user="&userid"
				pass="&pass"
				servertype=OBJECTSPAWNER;
		LIST SPAWNED SERVERS out=wkspc&i;
	quit;

	/* Count the number of total workspace servers were found. */

	proc sql noprint;
		select count(*) into :nwkspc from work.wkspc&i;
	quit;

	/* If any were found, add them to the wkspc dataset. */

	%if &nwkspc > 0 %then %do;
	proc sql;
		insert into work.wkspc
		select * from work.wkspc&i;
	quit;
	%end;

	/* If any were found, gather their IdleTime value. */

%if &nwkspc > 0 %then %do j=1 %to &nwkspc;

proc sql noprint;
	select SERVERID into:server_id1-:server_id%left(&nwkspc) from work.wkspc&i;
quit;
	proc iomoperate;
		connect host="&&host&i"
				port=&&port&i
				user="&userid"
				pass="&pass"
				servertype=OBJECTSPAWNER
				spawned="&&server_id&j";
			LIST ATTRIBUTE Category="Counters" Name="IOM.IdleTime" out=work.wkspci&j;
	quit;

	/* Add the server ID to the table containing the idle time. */

	data work.wkspci&j;
		set work.wkspci&j;
		server_id="&&server_id&j";
	run;

	/* Kill function */

	/* Define a macro that kills a given spawned server ID using the existing settings for host/port/user/pass */
	/* that we use above to get the idle time value */
	%macro killserver(id=);
		proc iomoperate;
			connect host="&&host&i"
					port=&&port&i
					user="&userid"
					pass="&pass"
					servertype=OBJECTSPAWNER
					spawned="&id";
				STOP SERVER;
		quit;
	%mend killserver;

	/* Check if kill is activated. */
	%if &kill = yes %then %do;

	data _null_;
		/* For each spawned server we found... */
		set work.wkspci&j;
		/* Convert the idle time to a number. */
		idle=input(VALUE,8.2);

		/* Check if the idle time is larger than our timeout value. */
		if idle > &timeout then do;
			/* If so, write a line to the log and call the killserver macro we defined above with the server_id of the high idle */
			put "NOTE: Server " server_id "idle time > &timeout at " idle ". Stopping server.";
			call execute('%killserver(id='||server_id||')');
		end;
		else do;
			/* If not, write a line to the log indicating it was evaluated. */
			put "NOTE: Server " server_id "idle time < &timeout at " idle ". Moving on.";
		end;
	run;

	%end;

	/* End Kill function */

	/* Join the spawned servers table for the spawner with the idle time. */

proc sql noprint;
	create table work.wkspcidle&j as select * from work.wkspc&i,work.wkspci&j where SERVERID=server_id;
quit;

/* Append the new table of server and idle time to a master table. */

	proc sql;
		insert into work.wkspcidle
		select SERVERCOMPONENT, LOGICALNAME, SERVERCLASS, PROCESSOWNER, SERVERID, CATEGORY, NAME, VALUE from work.wkspcidle&j;
	quit;


	%end;
%end;
%mend;

%getwkspc;

/* Convert the idle time value to a number. */

data work.final;
	set work.wkspcidle;
	keep SERVERCOMPONENT LOGICALNAME SERVERCLASS PROCESSOWNER SERVERID idle_time;
	idle_time=input(VALUE,8.2);
run;


proc print data=work.final; run;
