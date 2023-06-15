/******************************************************************************/
/* These two PROC IOMOPERATE procedures dynamically set the loggers and       */
/* levels in <SASConfig>/Levn/SASMeta/MetadataServer/logconfig.trace.xml and  */
/* return them to default. This is helpful for troubleshooting an issue as you*/
/* can run the first procedure to turn on trace logging, reproduce the failure*/
/* then run the second procedure to turn it off.                              */
/*                                                                            */
/* Note: These procedures must be run separately to have any effect, as the   */
/* second procedure undoes the actions of the first procedure. Edit the       */
/* "connect" options of the PROC IOMOPERATE procedure to those applicable for */
/* your Metadata host. For a Metadata cluster, these must be run against each */
/* host in the cluster.                                                       */
/* Date: 07SEP2016                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Turn ON Metadata trace logging. */

proc iomoperate;
	connect host='hostname'
			port=8561
			user='sasadm@saspw'
			pass='password'
			iomoptions='noredirect';

set attribute category="Loggers" name="App.Meta" value="Debug";
set attribute category="Loggers" name="App.OMI" value="Trace";
set attribute category="Loggers" name="Audit.Meta.Security" value="Trace";
set attribute category="Loggers" name="Audit.Authentication" value="Trace";
set attribute category="Loggers" name="Perf.Meta" value="Info";

quit;

/* Turn OFF Metadata trace logging. */

proc iomoperate;
	connect host='hostname'
			port=8561
			user='sasadm@saspw'
			pass='password'
			iomoptions='noredirect';

set attribute category="Loggers" name="App.Meta" value="NULL";
set attribute category="Loggers" name="App.OMI" value="NULL";
set attribute category="Loggers" name="Audit.Meta.Security" value="NULL";
set attribute category="Loggers" name="Audit.Authentication" value="NULL";
set attribute category="Loggers" name="Perf.Meta" value="NULL";

quit;
