# get_va_logs_v3.sh: Utility to collect logs of SAS Visual Analytics services running on SAS Viya 3.X environment UNIX.

## Overview:
This utility is for UNIX environments automates the collection of logs to diagnose problems with a new or existing SAS® of SAS Visual Analytics. 
This utility supports SAS Viya 3.x deployments and must be executed using the SAS Viya installer user ID on the target server.

## How to Use the Utility:

1. Save the get_va_logs_v3.sh file in a directory of your choice on the machine where SAS Viya 3.X services are installed and running.

2. Update Deployment Name *if necessary*

    The default deployment name for SAS Viya 3.x environments is set as viya. If your deployment name differs, update the script by modifying the following line:

    `DEPLOYMENT_NAME="viya" `
 
3. Set Execution Permissions

    Assign the necessary execution permissions to the script by running the following command in the UNIX terminal:

    `chmod 775 get_va_logs_v3.sh` 

4. Execute the Script

    Run the script using the following command:

`./get_va_logs_v3.sh`
 
5. During execution, you will be prompted to enter your SAS Technical Support Case Number. 

6. The script will produce output in the paths listed below.

## Output Location:

All of the output files are placed under the following folder structure based on the execution examples that are shown in the example

*Note:- Here <CASE_NO> will be the SAS Technical Support case number you will be entering.*

Log Directory: /tmp/*<CASE_NO>*/

Compressed TAR File: /tmp/*<CASE_NO>*.tar.gz

To manually upload the tar file, follow the instructions in [KB0036136 - How to upload and download files using the SASTSDrive file sharing server](https://sas.service-now.com/csm?id=kb_article_view&sysparm_article=KB0036136). You should then update the support request, stating that the logs are available. When completed, you can safely reclaim space in /tmp by removing the Logs and tar file.