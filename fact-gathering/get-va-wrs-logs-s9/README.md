# get-va-wrs-logs - Utility to collect log of SAS Visual Analytics and SAS Web Report Studio running on SAS 9.4 environment UNIX.
## Overview
This utility is for UNIX environments automates the collection of logs to diagnose problems with a new or existing SAS® of SAS Visual Analytics and SAS Web Report Studio. The script is for use with SAS 9.4 deployments.

This script must be executed using the SAS installer user ID on the server for which you are collecting information.

*Note: - You might need package called mlocate to use locate command in your Unix environment to make it work.*

## How to use
1. Save the get_va_wrs_logs.sh file in a directory of your choice on the machine where SAS 9.4 Server Mid-tier services are installed and running.

2. Set execution permissions for the get_va_wrs_logs.sh script by execution the following command:

    `chmod 755 get_va_wrs_logs.sh`

3. Run the script:

    `./get_va_wrs_logs.sh`

4. The script will prompt for which logs to collect as well as your SAS Technical Support case number.

5. The script will produce output in the paths listed below.

## Output Locations

All of the output files are placed under the following folder structure based on the execution examples that are shown in the example,

*Note:- Here <CASE_NO> will be the ServiceNow case number you will be entering.*

- Log: - /tmp/<CASE_NO>/
- TAR File: - /tmp/<CASE_NO>.tar.gz

To manually upload the tar file, follow the instructions in [KB0036136 - How to upload and download files using the SASTSDrive file sharing server](https://sas.service-now.com/csm?id=kb_article_view&sysparm_article=KB0036136). You should then update the support request, stating that the logs are available. When completed, you can safely reclaim space in `/tmp` by removing the Logs and tar file.