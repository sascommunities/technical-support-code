# SAS Technical Support Code
The **SAS Technical Support Code** project is a collection of sample code, scripts and tools written by SAS Technical Support to address common concerns we receive. These include, for example:
- Code that demonstrates functionality
- Code to perform common actions or generates commonly requested reports
- Scripts to gather information or files often requested by SAS Technical Support
- Scripts to correct common issues
## Organizational Structure
The project is separated into three main directories, with usage further separated to denote user versus administrator usage:
- fact-gathering
- fixes
- usage
  - administration
  - programming

The **fact-gathering** directory contains programs and scripts for gathering information from customers for troubleshooting purposes. Code to gather logs, version information, or current configuration can be found here. Think of these as *read* actions that are specifically for troubleshooting purposes.

The **fixes** directory contains programs and scripts for performing corrective actions. Code that updates configuration or files can be found here. Think of these as *write* actions *run once* to correct a specific problem.

The **usage** directory is divided into two main sub-directories, **administration** and **programming**. 

The **administration** sub-directory contains code and scripts for SAS administrators, performing potentially repetitive administrative actions. Code that generates a report on users and groups, or turns on and off trace logging can be found here.

The **programming** sub-directory contains code and scripts for SAS users. This is where you would find code snippets and examples for using SAS software.

## Naming Conventions
- Files should have an extension appropriate for the type of file they are (.sas, .py, .sh, .ps1, .r, etc.)
- For programs that are specific to SAS 9 or Viya (3.x, 2020+, or both), a suffix indicating this should be added. (_s9, _viya, _v3, or _vk)
- For single-function programs, the file name should be descriptive of what the program does, prefixed by an action (get, add, create, update, delete)
- If interacting with a specific server or service, this should be included in the file name