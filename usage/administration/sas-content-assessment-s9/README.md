# Starter_Script_SASContentAssessment: Starter execution scripts for use with SAS® Content Assessment to facilitate a fully automated execution.

## Overview:
Starter execution scripts intended as a starting point to help develop a robust process for executing [SAS® Content Assessment](https://support.sas.com/downloads/package.htm?pid=2465) applications following proven practices. These scripts include some basic error handling to stop the process in the event any application returns an error during execution.  The scripts can be executed manually or scheduled.  

Please refer to this SAS Technical Paper [SAS Content Assessment Proven Practice](https://NEEDS_UPDATING_WITH_PAPER_URL) for a detailed explanation. 

Two scripts are provided: 
- The Linux_Starter_Script_SASContentAssessment.sh should be used when running SAS® Content Assessment on a Linux environment. 
- The Win_Starter_Script_SASContentAssessment.sh should be used when running SAS® Content Assessment on a Windows environment. 

Both scripts have been tested with version 2025.01 of SAS® Content Assessment running on Red Hat Enterprise Linux 7 (64 bit) and Windows 2016 Server (64 bit). Providing the SAS® Content Assessment does not undergo significant changes, it is expected the scripts will maintain future compatibility. 

Always use the latest release of SAS® Content Assessment. Once you have a deployed SAS Viya platform, you should use the same corresponding version of SAS Content Assessment when planning and executing content migration.

## How to Use the Scripts:

1. Save the Starter_Script_SASContentAssessment script relevant for your operating system in a directory of your choice on the machine where SAS® Content Assessment has been setup and running.

2. Update the catpath variable to reflect your current SAS® Content Assessment location. For example:
	catpath="/opt/sasinside/contentassessment"

3. Set Execution Permissions

		Assign the necessary execution permissions to the script as per your operating system. 

4. Execute the Script

		Assuming all SAS® Content Assessment directory locations are kept with their default values, the script should run as is. 
 
## Notes:

Re-execution of the script results in previous data and reports being overwritten. If you want to keep the results, please ensure that a backup is made first.

The scripts can be executed manually or scheduled using a scheduler of your choice.

It is recommended to pipe the console output to a file and ensure this is kept as a log.  