/*

# Infile Trick

Code originally came from SAS Communitites user ChrisNZ in this thread. 
https://communities.sas.com/t5/SAS-Programming/How-to-delimit-large-dataset-28-Million-rows-into-700-variables/m-p/487676

The essence of where this code came from was a problem where the input was delimited data in a variable and the goal was to read it into an array. 
The naive approach involved a loop over the array and calls to the scan function. This was terribly slow since you have O(N^2) situation.
An absolutely mind melting trick was suggested by forum user Tom to use what they dubbed the \_infile\_ trick. 
In essence you get the datastep to allocate an input buffer, they copy the data from the dataset into the input buffer then use the input statements to chew through the data. 
AMAZING! 

*/
/*
 * SPDX-License-Identifier: Apache-2.0
 */

data HAVE;
  length ROW $8000;
  ROW='|||';
  do I=1 to 700;
    ROW=catx('|',ROW,put(i,z3.));
  end;
  do J = 1 to 1e4;
    output;
  end;
run;

data SPLIT;  /* Slow */
  set HAVE;
  array VAR(700) $10;
  do I = 1 to dim(VAR);
    VAR[I]=scan(ROW,I,'|','m');
  end;
run;
   
data SPLIT2;  /* Fast */
  set HAVE;
  infile sasautos(verify.sas) dsd dlm='|' lrecl=8000;
  input @1 @;
  _infile_=ROW;
  input @1 (VAR1-VAR700) (:$10.) @@;
run;

proc compare data=SPLIT compare=SPLIT2; 
run;
