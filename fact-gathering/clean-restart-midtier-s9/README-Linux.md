# Clean Restart SAS 9.4x Midtier  And Collect logs scripts.

There are two scripts as part of clean restart midtier procedure.

- clean_midtier_s9.sh : This script is used to backup all midtier WebServer
  and WebAppServer logs. It creates backup directories in respective server
  directories and moves all historical logs to that directory. Further it cleans
  ActiveMQ and Gemfire/Geode (cache locator) directories.

- collect_latest_midtier_logs_configs_s9.sh : This script collects all the latest logs
  as well as configs from all the midtier servers.

**NOTE**:  **collect_latest_midtier_logs_configs_s9.sh script can be used independently as well.**

## Prerequisite/Procedure

- All midtier services need to be stopped.
- Run clean_midtier_s9.sh . Kill dangling midtier pids on the node you are
  running this script on.
- Start midtier services and run collect_latest_midtier_logs_configs_s9.sh.
- Bash Shell

**Note**: clean_midtier_s9.sh should be run by experianced SAS Administrators or under their supervision.
There is a risk that customers may kill unrelated pids on their midtier servers.

## Usage

# clean_midtier_s9.sh :

Each parameter is required to be set.

./clean_midtier_s9.sh -c <true|false> -d <SAS-configuration-directory/Levn>

-c | Clean cache locator only - true/false

-d | SAS-configuration-directory/Levn

# collect_latest_midtier_logs_configs_s9.sh :

Each parameter is required to be set.

./collect_latest_midtier_logs_configs_s9.sh -t <all|latest> -d <SAS-configuration-directory/Levn>

-t | Collect "all" OR "latest" logs only - all/latest

-d | SAS Configuration directory, for example: /opt/sas/config/Lev1/

-w | Script's work directory, for example: /tmp/ IMPORTANT: The OS user must have read and write privileges to that
directory

## Cli Steps Example

- <CONFIG-PATH>/Lev1/sas.servers.mid stop
- ./clean_midtier_s9.sh
- Kill all dangling midtier pids.
- <CONFIG-PATH>/Lev1/sas.servers.mid start
- ./collect_latest_midtier_logs_configs_s9.sh

## Script Output

- collect_latest_midtier_logs_configs_s9.sh creates a zip file
  log-bundle-date.zip in specified dir example /tmp directory
  which can be uploaded to track for further analysis.
  Please read the script header for details.
