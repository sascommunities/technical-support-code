@echo off
setlocal 

REM Windows Batch Script that runs the SAS Content Assessment applications inventoryContent, profileContent, gatherSASCode, codeCheck, i18nCodeCheck, and publishAssessedContent.
REM DATE: 31MAR2025

REM Copyright © 2025, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
REM SPDX-License-Identifier: Apache-2.0

REM Set your path to the unpacked SAS 9 Content Assessment files and the location to log output from this script
SET "catpath=D:\CAT\SAS9ContentAssessment202501win"

REM END OF CUSTOM VARIABLE SETUP

REM Set a timestamp for the output
SET timestamp=%DATE:~10,4%%DATE:~4,2%%DATE:~7,2% - %TIME:~0,2%.%TIME:~3,2%.%TIME:~6,2%


echo.
echo Running: %~n0
echo catpath = %catpath%
echo Time: %timestamp%
echo   -Please wait....

echo.
echo ############################################################################
echo # INVENTORY                                                                #
echo ############################################################################
echo. 
call :check_and_call: "%catpath%\assessment\inventoryContent.exe"

echo.
echo ############################################################################
echo # PROFILE                                                                  #
echo ############################################################################
echo. 
call :check_and_call: "%catpath%\assessment\profileContent.exe"

echo.
echo ############################################################################
echo # GATHER SAS CODE                                                          #
echo ############################################################################
echo. 
call :check_and_call: "%catpath%\assessment\gatherSASCode.exe" --all

echo.
echo ############################################################################
echo # CODE CHECK                                                               #
echo ############################################################################
echo. 
echo ########### Running SASObjCode - "%catpath%\assessment\gatheredSASCode"
echo.
call :check_and_call: "%catpath%\assessment\codeCheck.exe" --scan-tag SASObjCode --source-location "%catpath%\assessment\gatheredSASCode"
echo.
echo ########### Running BaseSASCode - "%catpath%\assessment\pathslist.txt"
echo.
call :check_and_call: "%catpath%\assessment\codeCheck.exe" --scan-tag BaseSASCode --sources-file "%catpath%\assessment\pathslist.txt"

echo.
echo ############################################################################
echo # CODE CHECK FOR INTERNATIONALIZATION                                      #
echo ############################################################################
echo. 
echo ########### Running SASObjCode - "%catpath%\assessment\gatheredSASCode"
echo.
call :check_and_call: "%catpath%\assessment\i18nCodeCheck.exe" --scan-tag SASObjCode --source-location "%catpath%\assessment\gatheredSASCode"
echo.
echo ########### Running BaseSASCode - "%catpath%\assessment\pathslist.txt"
echo.
call :check_and_call: "%catpath%\assessment\i18nCodeCheck.exe" --scan-tag BaseSASCode --sources-file "%catpath%\assessment\pathslist.txt"

echo. 
echo ############################################################################
echo # PUBLISH                                                                  #
echo ############################################################################
echo. 
call :check_and_call: "%catpath%\assessment\publishAssessedContent.exe" --create-uploads --datamart-type inventory  --encrypt-aes
call :check_and_call: "%catpath%\assessment\publishAssessedContent.exe" --create-uploads --datamart-type profile  --encrypt-aes
call :check_and_call: "%catpath%\assessment\publishAssessedContent.exe" --create-uploads --datamart-type codecheck  --encrypt-aes
call :check_and_call: "%catpath%\assessment\publishAssessedContent.exe" --create-uploads --datamart-type i18n  --encrypt-aes


REM set completion message
IF %ERRORLEVEL%==0 (SET catscriptmsg=SUCCESS) ELSE (SET catscriptmsg=ERROR  )
echo. 
echo ############################################################################
echo # SAS Content Assessment %catscriptmsg%                                           #
echo ############################################################################
echo. 

endlocal
goto :eof

REM A function to call and check for errors
:check_and_call
	IF %ERRORLEVEL%==0 (
		call %*
	) 
	
	IF %ERRORLEVEL% NEQ 0 (
		echo Error Detected: abort
		exit /b %ERRORLEVEL%
	)
	goto :eof