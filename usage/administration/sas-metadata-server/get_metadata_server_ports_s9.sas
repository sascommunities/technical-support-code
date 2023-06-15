/******************************************************************************/
/* This program will extract all defined ports in Metadata and their          */
/* associated services.                                                       */
/* Date: 15JAN2018                                                            */
/******************************************************************************/

/* Copyright 2023 SAS Institute, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */

/* Metadata connection information: */

%let metaserve=meta.demo.sas.com;
%let metaport=8561;
%let userid=sasadm@saspw;
%let pass=password;

/* End edit. */

/* Connect to Metadata Server */

options	metaserver="&metaserve"
		metaport=&metaport
		metauser="&userid"
		metapass="&pass"
		metarepository=Foundation
		metaprotocol=BRIDGE;

data servers;

/* Declare and initialize variables. */

length 	type id $ 17 server_uri conn_uri $ 50 server_name conn_name $ 256 conn_prot conn_port $ 5 conn_port_num 3;
label 	server_name="Server Name"
		conn_name="Connection Name"
		conn_prot="Connection Protocol"
		conn_port_num="Port";
call missing (of _character_);
drop obj server_cnt server_uri type id rc n conn_cnt o conn_uri conn_port_num;
/* Define the query to locate servers in Metadata. */
obj="omsobj:ServerComponent?@Id contains '.'"; 

/* Count servers defined in Metadata. */
server_cnt=metadata_resolve(obj,type,id);
put server_cnt=;

/* If servers exist, extract their information. */

if server_cnt > 0 then do n=1 to server_cnt;
	rc=metadata_getnobj(obj,n,server_uri);
	rc=metadata_getattr(server_uri,"Name",server_name);
	conn_cnt=metadata_getnasn(server_uri,"SourceConnections",1,conn_uri);
	if conn_cnt > 0 then do o=1 to conn_cnt;
	rc=metadata_getnasn(server_uri,"SourceConnections",o,conn_uri);
	rc=metadata_getattr(conn_uri,"Name",conn_name);
	rc=metadata_getattr(conn_uri,"CommunicationProtocol",conn_prot);
	conn_prot=upcase(conn_prot);
	rc=metadata_getattr(conn_uri,"Port",conn_port);
	conn_port_num=input(trim(conn_port),5.);
	if conn_port_num ne 0 then output; /* Only output if a port is defined. */
	end;
end;
else put "ERROR: No server definitions found in Metadata.";
run;
proc sort data=servers; /* Sort the data. */
	by server_name;
run;
proc report data=servers; 
	title "Port use defined in Metadata Server &metaserve";
run;