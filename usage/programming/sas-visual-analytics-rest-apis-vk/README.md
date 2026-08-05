# SAS Visual Analytics REST APIs

## Overview

This project contains five SAS programs that demonstrate how to interact with SAS Visual Analytics REST APIs to retrieve report information and export reports in various formats.

These APIs allow you to:

- Retrieve report metadata
- Retrieve report content in XML format
- Export reports as PDF documents
- Export reports as PNG images
- Export reports as ZIP report packages

## Prerequisites

Before running any of the programs, update the hostname and the report ID at the beginning of each SAS program.

Locate the following section:

```sas
/* Specify host and Report ID. */
%let baseurl=https://hostname;
%let reportId=<report_id>;
```

Replace the values with:

- "hostname": Your SAS Viya host URL
- "reportId": Your report ID

## Example:

```sas
/* Specify host and Report ID. */
%let baseurl=https://viya.example.com;
%let reportId=12345678-1234-1234-1234-123456789abc;
```

## Files Included

| File | Description |
|---|---|
| "GetReport.sas" | Retrieves information about a specific report. |
| "ExportXML.sas" | Retrieves report content and saves it as XML. |
| "ExportPNG.sas" | Exports a report or report object as a PNG image. |
| "ExportPDF.sas" | Exports a report as a PDF document. |
| "ExportPackage.sas" | Exports a report package as a ZIP file. |

## 1. "GetReport.sas"

Retrieves metadata for a specific report.

### Required Changes

The only changes required for this code are to update the hostname and the report ID at the beginning of the program.

### Output

Returns report metadata in a table format.

## 2. "ExportXML.sas"

Retrieves report content and saves it as an XML file.

### Required Changes

Specify the output file location:

```sas
filename report "/path/to/report/<Export XML name>.xml";
```

## Example:

```sas
filename report "/home/sasuser/report.xml";
```

### Output

Creates an XML file containing the report definition and content.

## 3. "ExportPNG.sas"

Exports a report or report object as a PNG image.

### Required Changes

Specify the output file location:

```sas
filename report "/path/to/report/<Export Image name>.png";
```

Specify the image size:

```sas
url="&baseurl/visualAnalytics/reports/&reportId/png?size=1024px,768px";
```

> "Note:" The size values included in the code are provided as examples. Update them as needed to suit your environment.

## Example:

```sas
filename report "/home/sasuser/report.png";
url="&baseurl/visualAnalytics/&reportId/12345678-1234-1234-1234-123456789abc/png?size=1920px,1080px";
```

### Output

Creates a PNG image of the specified report.

## 4. "ExportPDF.sas"

Exports a report as a PDF document.

### Required Changes

Specify the output file location:

```sas
filename report "/path/to/report/<Export PDF name>.pdf";
```

## Example:

```sas
filename report "/home/sasuser/report.pdf";
```

### Output

Creates a PDF version of the report.

## 5. "ExportPackage.sas"

Exports a report package as a ZIP file.

### Required Changes

Specify the output file location:

```sas
filename report "/path/to/report/<Export package name>.zip";
```

## Example:

```sas
filename report "/home/sasuser/report.zip";
```

### Output

Creates a ZIP package containing the report and associated resources.

## Finding the Report ID

The APIs require a valid SAS Visual Analytics report ID.

A report ID can typically be obtained from:

- "SAS Environment Manager": Navigate to "Content" and open the folder where your report is stored. Select the report, then open the "Details" section. From there, expand the "More" drop-down menu and locate "URI", where the Report ID is displayed.
- "SAS Drive": Navigate to the "All" tab and open the folder where your report is stored. Select the report, then open the "Details" section. From there, expand the "More" drop-down menu and locate "URI", where the Report ID is displayed.

## Example Report ID in Environment Manager:

```text
Pathname: /reports/reports/12345678-1234-1234-1234-123456789abc
```

Report ID:

```text
12345678-1234-1234-1234-123456789abc
```

## Notes

- Ensure the specified output directories exist and that the SAS Compute Server has write access to them.
- The authenticated user must have permission to access the report being exported.
- Large reports may take longer to export, particularly when generating PNG, PDFs, and packages.
- The image size specified in "ExportPNG.sas" can be adjusted as required.

## Disclaimer

These sample programs are provided as examples for interacting with SAS Visual Analytics REST APIs. They may require modification to suit your environment, authentication configuration, and security requirements. Always validate the output and test in a non-production environment before deploying to production.
