/*

# Numeric Comparison

Some developers and programmers get caught out by potential pitfalls with floating point numbers. 
Occasionally a result might not make sense at first. 
Often this result of the how the machine is representing numbers. 
With floating point numbers in our modern computers you have only 64 bits to represent them.
Clearly with a finite number of representations (2^64) you can't represent all floating point numbers because there are infinitely many of them. 
What this means is that inside the machine you actually work with close approximations most of the time.

Take this concrete example. 
Consider the number 0.92478 as an example, inside our machines we can't represent this exactly. 
Here are the two closest numbers the machines can actually store.

  0.9247800000000000464339677819225

  0.9247799999999999354116653194069

This is a physical limitation of the design of the chip crunching the numbers. 
It is up to you, the software developer, to understand this and account for it in your programs.  
When you make comparisons of numbers you need to consider the meaning of the number, what it is counting, and decide how close do two numbers need to be to be considered the same. 
Imagine you get dropped on a random beach on the globe and I do too. 
If you and I counted all the grains of sand and we come back with a number that is within 100 grains of sand we would likely conclude we were put onto the same beach. 
Depending on the application you have you can use a big epsilon, in others it needs to be quite small. 
The key is that you need to come up with the epsilon that makes sense for your program.

*/

/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

data _null_;

    /* Define x, assign the value of x to y */    
    x = 0.92478;
    y = x;

    /* Incorrect comparison
       They are currently equal because the bits are exactly the same */
    equals = (x = y);
    put " [ Incorrect ] " x= y= equals=;
    put x= binary64.;
    put y= binary64.;

    /* Print the hex respresentation of what the least 
       significant digits look like    */
    length top_byte $1;
    addr_y = addrlong(y);
    top_byte = peekclong(addr_y,1);
    put top_byte= hex.;
    
    /* Replace a single bit of the number. The least significant 1 is now a 0 
       When its printed you end up with two numbers that look the same but they
       are not */
    call pokelong(0Ex, addr_y, 1);

    /* Incorrect comparison
       x and y are not the same anymore. They are extremely close to one another
       but they are not the same */
    equals = (x = y);
    put " [ Incorrect ] " x= y= equals=;
    put x= binary64.;
    put y= binary64.;


    /* Better comparison, compare for being _very very_ close */
    equals = abs(x - y) < ( 0.000000001 );
    put " [ Better ] " x= y= equals=;
    put x= binary64.;
    put y= binary64.;

run;

