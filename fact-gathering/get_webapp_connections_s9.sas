/* This program pulls the web application connection details from Metadata into a SAS data set called "cons" */
/* that includes the protocol, host, port and URL, and the Metadata path to the configuration object. */
/* It will write this information to the log as well as output in a report. */

/* Date: 09JUN2021 */

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Provide Metadata connection information. */
options metaserver='meta.demo.sas.com'
metaport=8561
metaprotocol='bridge'
metauser='sasadm@saspw'
metapass='password'
metarepository='Foundation'
metaconnect='NONE'
;
/* End edit. */

/* Create a data set, cons, to hold the values. */
data cons;
/* Initialize variables. */
  length host $ 255
  port $ 8
  protocol $ 5
  endpoint $ 255
  type $ 15
  id $ 17
  uri $ 40
  name $ 14
  suri dcuri appname url path folder ppath $ 512
  turi pturi $ 29;
  keep name protocol host port endpoint appname url path;
  call missing ( of _character_);
  /* Define a search for connection definitions. */
  obj = "omsobj:TCPIPConnection?@Name='Connection URI' or @Name='External URI'";
  /* Count how many objects match the query. */
  concount = metadata_resolve(obj,type,id);
  /* If any are found, loop through each one, pulling attributes. */
  if concount > 0 then do i = 1 to concount;
    rc = metadata_getnobj(obj,i,uri);
    rc = metadata_getattr(uri,"Name",name);
  /* Internal URIs are called "Connection URI". */
  /*Rename it so it aligns with the external URI name. */
    if trim(name)='Connection URI' then name = 'Internal URI';
    rc = metadata_getattr(uri,"CommunicationProtocol",protocol);
    rc = metadata_getattr(uri,"HostName",host);
    rc = metadata_getattr(uri,"Port",port);
    rc = metadata_getattr(uri,"Service",endpoint);
    /* Pull the application associated with the connection. */
    rc = metadata_getnasn(uri,"Source",1,suri);
    rc = metadata_getnasn(suri,"DescriptiveComponent",1,dcuri);
    rc = metadata_getattr(dcuri,"Name",appname);
    /* Pull the path of that object. */
    rc = metadata_getnasn(dcuri,"Trees",1,turi);
    rc = metadata_getattr(turi,"Name",folder);
    path=folder;
    /* Determine if the metadata folder is top-level */
    parent_rc=metadata_getnasn(turi,"ParentTree",1,pturi);
    /* If not, this loop assembles the metadata path,*/
    /* as these are nested "Tree" objects. */
    if parent_rc > 0 then do while (parent_rc > 0);
      rc=metadata_getattr(pturi,"Name",ppath);
      path=cats(ppath,"\",path);
      parent_rc=metadata_getnasn(pturi,"ParentTree",1,pturi);
    end;
    path=cats("\",path);
    /* Build the full URL from the protocol,*/
    /* host, port and endpoint definitions. */
    url=strip(protocol) || '://' || strip(host) ||
    ':' || strip(port) || strip(endpoint);
    /* Don't output SASTheme as the */
    /* information for it is not stored here. */
    rc=find(appname,"SASTheme");
    if rc ne 1 then do;
      /* Write the url and application name to the log. */
      put name url;
      put appname;
      put path;
      put;
      output;
    end;
  end;
run;

/* Sort the data set by the application name. */
proc sort data=cons;
  by appname;
run;

/* Print the dataset. */
proc print data=cons;
  var name url appname;
  title  'Internal and External Connections (except SASThemes)';
  title2 'Listed by Application';
run;