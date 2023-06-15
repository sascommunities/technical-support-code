/* This code demonstrates how to base64 encode/decode strings within a SAS DATA step */
/* using the base64x format/informat. */
/* Date: 28MAR2023 */

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

%let string=stringtobeencoded;

data _null_;
	base=put("&string",$base64x80.);
	call symput("base",base);
run;

%put encoded=&base;

data _null_;
decode=input("&base",$base64x80.);
call symput("decode",decode);
run;
%put decoded=&decode;