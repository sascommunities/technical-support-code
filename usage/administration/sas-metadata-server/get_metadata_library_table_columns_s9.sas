/******************************************************************************/
/* This program extracts defined columns for all libraries in Metadata.       */
/* It must be edited with valid connection information for the Metadata       */
/* server and as it connects to a Metadata Server is only valid in SAS 9.x.   */
/* Date: 15SEP2016                                                            */
/******************************************************************************/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/* --- Edit with your Metadata host name and credentials --- */
options
  metaserver="meta.demo.sas.com"
  metaport=8561
  metauser="sasadm@saspw"
  metapass="password"
  metarepository=Foundation
  metaprotocol=BRIDGE;
/* End Edit */

data work.columns; /* Create dataset work.columns to store the column data. */

/* Define the variables. */
length
  SASLibrary_uri $ 35
  LibraryName $ 256
  PhysicalTable_uri $ 38
  PhysicalTable_Id $ 17
  PhysicalTable_Name $ 256
  LibraryID $ 17
  Column_uri $ 31
  Column_id $ 17
  Column_name $ 256;

/* Define initial values */

call missing(of _character_);
librc=0;
objrc=0;
colrc=0;
arc=0;
n=1;
m=1;
o=1;

/* Stipulate which variables to store from one row to the next. */

retain
  SASLibrary_uri
  LibraryName
  PhysicalTable_uri
  PhysicalTable_Id
  PhysicalTable_Name
  LibraryID;

/* Stipulate which columns should remain in the */
/* final output (cut out the querying variables) */

keep LibraryName PhysicalTable_Name Column_name;

/* Get the URI of the first SAS Library found in */
/* Metadata (if none, librc will be negative). */
/* As n increases through the do loop past the index */
/* number of the last library, librc will become negative, ending the loop. */

librc=metadata_getnobj("omsobj:SASLibrary?@Id contains '.'",n,SASLibrary_uri);
  do while(librc>0);

/* Query Metadata for the Id and Name of the */
/* Library URI acquired in the previous section. */

    arc=metadata_getattr(SASLibrary_uri,"Id",LibraryID);
    arc=metadata_getattr(SASLibrary_uri,"Name",LibraryName);

/* Get the URI of the first Table stored in the first library. */

    objrc=metadata_getnobj("omsobj:PhysicalTable?PhysicalTable[TablePackage/SASLibrary[@Id='"||LibraryID||"']]",m,PhysicalTable_uri);
    do while(objrc>0);

/* Get the Id and Name of the Table */

      arc=metadata_getattr(PhysicalTable_uri,"Id",PhysicalTable_Id);
      arc=metadata_getattr(PhysicalTable_uri,"Name",PhysicalTable_Name);

/* Get the URI of the first column in the first table in the first library */

      colrc=metadata_getnobj("omsobj:Column?Column[Table/PhysicalTable[@Id='"||PhysicalTable_Id||"']]",o,Column_uri);
      do while(colrc>0);

/* Get the Id and Name of the column */

        arc=metadata_getattr(Column_uri,"Id",Column_id);
        arc=metadata_getattr(Column_uri,"Name",Column_name);
        output; /* output the row */
        o+1; /* increment the index of the column search */
        colrc=metadata_getnobj("omsobj:Column?Column[Table/PhysicalTable[@Id='"||PhysicalTable_Id||"']]",o,Column_uri); /* read the next column uri */
      end;
      o=1; /* reset the column search index for the next table */
      m+1; /* increment the index of the table search */
      objrc=metadata_getnobj("omsobj:PhysicalTable?PhysicalTable[TablePackage/SASLibrary[@Id='"||LibraryID||"']]",m,PhysicalTable_uri); /* read the next table uri */
    end;
    m=1;/* reset the table search index for the next library */
    n+1; /* increment the index of the library search */
    librc=metadata_getnobj("omsobj:SASLibrary?@Id contains '.'",n,SASLibrary_uri); /* read the next library uri */
  end;
run;
