/******************************************************************************/
/* This program creates a set of tables from Metadata containing information  */
/* about jobs and flows.                                                      */
/* These tables are:                                                          */
/* Flows - a tables of defined flows                                          */
/* Flowsched - a table of scheduled flows and their schedules                 */
/* Jobs - a table of deployed jobs and their associated data servers          */
/* dsbs - a table of data step batch servers and their attributes             */
/* cmd - a table of any customized commands for jobs.                         */
/* Date: 22JUN2020                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Provide connection to Metadata */
%let mduser=sasadm@saspw;
%let mdpass=password;
%let mdserver=meta.demo.sas.com;
%let mdport=8561;

/* Specify Data Step Batch Server values */
/* 9.4 Values */
%let dsbslogprop=BatchServer.DataStep.Property.LogDir.xmlKey.txt;
%let dsbslogext=BatchServer.DataStep.Property.LogExt.xmlKey.txt;
%let dsbscmdline=BatchServer.DataStep.Property.CmdLine.xmlKey.txt;

/* 9.3 Values */
/*%let dsbs=%str('SASCompute1 - SAS Data Step Batch Server');*/
/*%let dsbslogprop=%str(Logs Directory);*/
/*%let dsbslogext=%str(Rolling Log Options);*/
/*%let dsbscmdline=%str(Command Line);*/


/* Set Metadata connection options based on macro variables set above. */
options metaserver="&mdserver"
metaport=&mdport
metaprotocol='bridge'
metauser="&mduser"
metapass="&mdpass"
metarepository='Foundation'
metaconnect='NONE'
;

/* Pull properties for the Data Step Batch Server(s) */
data dsbs (keep=dsbs_id dsbsname dsbscmdline dsbslogpath dsbslogext);
	length type id prop_uri dsbs_uri $ 50 prop_name $ 255 propval dsbsname dsbscmdline dsbslogpath dsbslogext  $ 1024 dsbs_id $ 17;
	call missing (of _character_);
	dsbsobj="omsobj:ServerComponent?@PublicType='Server.DataStepBatch'";
	dsbscount=metadata_resolve(dsbsobj,type,id);
	if dsbscount ge 1 then do j=1 to dsbscount;
		rc=metadata_getnobj(dsbsobj,j,dsbs_uri);
		rc=metadata_getattr(dsbs_uri,"Id",dsbs_id);
		rc=metadata_getattr(dsbs_uri,"Name",dsbsname);
		propcount=metadata_getnasn(dsbs_uri,"Properties",1,prop_uri);
		if propcount > 0 then do i=1 to propcount;
			rc=metadata_getnasn(dsbs_uri,"Properties",i,prop_uri);
			rc=metadata_getattr(prop_uri,"Name",prop_name);
			rc=metadata_getattr(prop_uri,"DefaultValue",propval);
			if prop_name="&dsbscmdline" then do;
				dsbscmdline=propval;
			end;
			else if prop_name="&dsbslogprop" then do;
				dsbslogpath=propval;
			end;
			else if prop_name="&dsbslogext" then do;
				dsbslogext=propval;
			end;
		end;
		output;
	end;
run;

/* Create table of flow IDs and schedule details */

data flowsched (keep=flow_id event_condition schedule);
	length type id flow_uri step_uri event_uri prop_uri prop_name $ 50 flow_name $ 255 event_condition prop_val schedule $ 1024 flow_id $ 17;
	call missing(of _character_);
	flow_obj="omsobj:JFJob?@PublicType='DeployedFlow'";
	flowcount=metadata_resolve(flow_obj,type,id);
	put "NOTE: Found " flowcount "flows.";
	if flowcount ge 1 then do i=1 to flowcount;
		rc=metadata_getnobj(flow_obj,i,flow_uri);
		rc=metadata_getattr(flow_uri,"Id",flow_id);
			rc=metadata_getnasn(flow_uri,"Steps",1,step_uri);
			rc=metadata_getnasn(step_uri,"TriggeringEvents",1,event_uri);
				rc=metadata_getattr(event_uri,"Condition",event_condition);
				propcount=metadata_getnasn(event_uri,"Properties",1,prop_uri);
				if propcount ge 1 then do l=1 to propcount;
					rc=metadata_getnasn(event_uri,"Properties",l,prop_uri);
					rc=metadata_getattr(prop_uri,"Name",prop_name);
					if prop_name = "Definition" then do;
					rc=metadata_getattr(prop_uri,"DefaultValue",prop_val);
					schedule=trim(prop_val);
					output;
					end;
		end;
	end;
run;

/* Create table of flow IDs and Names */

data flows (keep=flow_id flow_name);
	length type id flow_uri  $ 50 flow_name $ 255 flow_id $ 17;
	call missing(of _character_);
	flow_obj="omsobj:JFJob?@PublicType='DeployedFlow'";
	flowcount=metadata_resolve(flow_obj,type,id);
	put "NOTE: Found " flowcount "flows.";
	if flowcount ge 1 then do i=1 to flowcount;
		rc=metadata_getnobj(flow_obj,i,flow_uri);
		rc=metadata_getattr(flow_uri,"Name",flow_name);
		rc=metadata_getattr(flow_uri,"Id",flow_id);
		output;
	end;
run;

/* Create table of job details. */
data jobs (keep=job_name dir_name file_name dsbs_id job_id);
length type id job_uri file_uri dir_uri dsbs_uri $ 50  job_name dir_name file_name $ 255 dsbs_id job_id $ 17;
call missing(of _character_);
jobobj="omsobj:JFJob?@PublicType='DeployedJob'";
jobcount=metadata_resolve(jobobj,type,id);
if jobcount ge 1 then do i=1 to jobcount;
	rc=metadata_getnobj(jobobj,i,job_uri);
	rc=metadata_getattr(job_uri,"Name",job_name);
	rc=metadata_getattr(job_uri,"Id",job_id);
	rc=metadata_getnasn(job_uri,"SourceCode",1,file_uri);
	rc=metadata_getattr(file_uri,"FileName",file_name);
	rc=metadata_getnasn(file_uri,"Directories",1,dir_uri);
	rc=metadata_getattr(dir_uri,"DirectoryName",dir_name);
	rc=metadata_getnasn(job_uri,"TargetSpecifications",1,dsbs_uri);
	rc=metadata_getattr(dsbs_uri,"Id",dsbs_id);
	output;
end;
run;

/* Create table of custom command lines and their associated job. */
data cmd (keep=job_id cmd_val);
	length type id cmd_uri step_uri job_uri $ 50 cmd_val $ 1024 job_id $ 17;
	call missing (of _character_);
	cmdobj="omsobj:Property?Property[@Name='CmdLine'][AssociatedObject/TransformationStep/Transformations/JFJob]";
	cmdcount=metadata_resolve(cmdobj,type,id);
	if cmdcount ge 1 then do i=1 to cmdcount;
		rc=metadata_getnobj(cmdobj,i,cmd_uri);
		rc=metadata_getattr(cmd_uri,"DefaultValue",cmd_val);
		rc=metadata_getnasn(cmd_uri,"AssociatedObject",1,step_uri);
		rc=metadata_getnasn(step_uri,"Transformations",1,job_uri);
		rc=metadata_getattr(job_uri,"Id",job_id);
		output;
	end;
run;


/* Get Flow/Job associations */
data flowjobs (keep=flow_id job_id);
length type id flow_uri act_uri step_uri job_uri $ 50 flow_name $ 255 flow_id job_id $ 17;
call missing (of _character_);
flowobj="omsobj:JFJob?@PublicType='DeployedFlow'";
flowcount=metadata_resolve(flowobj,type,id);
if flowcount ge 1 then do i=1 to flowcount;
	rc=metadata_getnobj(flowobj,i,flow_uri);
	rc=metadata_getattr(flow_uri,"Id",flow_id);
	actcount=metadata_getnasn(flow_uri,"JobActivities",1,step_uri);
	if actcount ge 1 then do j=1 to actcount;
		rc=metadata_getnasn(flow_uri,"JobActivities",j,act_uri);
		stepcount=metadata_getnasn(act_uri,"Steps",1,step_uri);
		if stepcount ge 1 then do k=1 to stepcount;
			rc=metadata_getnasn(act_uri,"Steps",k,step_uri);
			jobcount=metadata_getnasn(step_uri,"Transformations",1,job_uri);
			if jobcount ge 1 then do l=1 to jobcount;
				rc=metadata_getnasn(step_uri,"Transformations",l,job_uri);
				rc=metadata_getattr(job_uri,"Id",job_id);
				output;
			end;
		end;
	end;
end;
run;

/* Extract sysin and log values from custom command. This is currently limited to UNIX-like paths. */

data cmd (keep=job_id cmd_val log sys);
	set cmd;
	if _N_=1 then do;
	retain logpatternID syspatternID;
	logpattern='/-log[[:space:]]+\/[A-z0-9\/\.]+/';
	syspattern='/-sysin[[:space:]]+\/[A-z0-9\/\.]+/';
	logpatternID=prxparse(logpattern);
	syspatternID=prxparse(syspattern);
	end;
	call prxsubstr(logpatternID,cmd_val,position,length);
	log=substr(cmd_val,position+5,length-5);
	call prxsubstr(syspatternID,cmd_val,position,length);
	sys=substr(cmd_val,position+7,length-7);
run;