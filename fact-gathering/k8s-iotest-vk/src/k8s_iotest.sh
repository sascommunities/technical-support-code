#!/bin/bash
#
# Copyright (c) 2025 SAS Institute Inc. 
# Unpublished - All Rights Reserved 
#
# ============================
# K8S Automated Iotest Script
# Version 1.0.00
# Build 202501020100
# ============================
#
# k8s_iotest.sh
# This script tests a machine's bandwidth by executing dd commands
#   that simulate SAS Read and Write activity. Results serve as a
#   litmus test for that machine and are packaged up with various
#   system information into k8s_iotest_[HOST]_[DATE]-[TIME].tar.gz.
#
# USAGE
# ./k8s_iotest.sh [OPTION]
#   --help	    display this help and exit
#   --version   output version information and exit
#   -t          target directory to test
#
# RETURN CODES
#  0  : Success
#  1  : General error
#  2  : Usage error or invalid parameter
#
# ====================================================================
# REVISION HISTORY
# ====================================================================
# Date        Developer   Change
# ----        ---------   ------
# 2016-07-13  jikuel      Initial program written
# 2016-08-22  jikuel      Added edge-case checks and comments
# 2016-09-28  jikuel      Formatted and cleaned up output
# 2016-12-21  jikuel      Added validation checks and altered output
# 2018-01-29  jikuel      Increased minimum RAM per physical core
#                             requirement from 4 GB to 8 GB
# 2018-03-13  jikuel      Lowered RAM requirements with added logging
# 2018-04-26  jikuel      Fixed edge case with invalid file sizes
# 2018-06-11  jikuel      Correctly handle dirs with special chars
# 2020-05-01  jikuel      Added support for RHEL 8 and CentOS
# 2020-07-22  jikuel      Updated test file & dir names to include
#                             hostname and datetimes
# 2020-11-24  jikuel      Fixed potential issue with relative paths
# 2020-12-09  jikuel      Output iterations to results file
# 2022-11-22  jikuel      Fixed minor bug
# 2025-01-02  sbralg      Added support for Alpine Linux
#

# ====================================================================
# VARIABLES
# ====================================================================
START_TIME=$(date)
SCRIPT_NAME="K8S Iotest"
SCRIPT_VERSION="0.1.00"
SCRIPT_BUILD_ID="202501020100"
BASEDIR=$(dirname $(readlink -f $0))
BASEDIR_SHORT=$(dirname $0)
PROG=${0##*/}
FILES=""
LOG=""
UNAME=$(uname)
DATE=$(date +%Y%m%d)
DATETIME=$(date +%y%m%d-%H%M)
OPTIONS=${*}
RC=0
BLOCKSIZE=64
MAS=0
ASC=0
LO=0
NOCLEAN=0
FACTOR=""
EAWS=()
LO_EAWS=()
WARNINGS=()

# ====================================================================
# COMMON FUNCTIONS
# ====================================================================

# print usage
usage ()
{
	echo ""
	echo "<<USAGE>>  ${PROG} -t <target directory>"
	echo ""
	echo " Function: Run dd write and read tests to a SAS filesystem to test throughput."
	echo "           Results will be stored in k8s_iotest_[HOST]_[DATE]-[TIME].results."
	echo "           All output and various system info will be packaged into k8s_iotest_[HOST]_[DATE]-[TIME].tar.gz."
	echo ""
	echo "           The target directory is the SAS read/write filesystem to test."
	echo ""
}

# print version
version ()
{
echo -e "
${SCRIPT_NAME}
Version: ${SCRIPT_VERSION}
Build: ${SCRIPT_BUILD_ID}

Copyright (c) 2025 SAS Institute Inc. 
Unpublished - All Rights Reserved.\n"
}

check_commands ()
{
	CMDS=(awk bc cat cp cut date dd df dirname egrep grep hostname mkdir mount readlink rm sed sort sync tail tar tee touch uname uniq wc /usr/bin/time)
	
	for CMD in "${CMDS[@]}";
	do
		if ! CMDTYPE="$(type -p ${CMD})" || [ -z "${CMDTYPE}" ];
		then 
			MSG="<<ERROR>>    required command '${CMD}' not found. install before continuing."
			store_eaws
			RC=1
		fi
	done

	if [ "${RC}" -ne 0 ];
	then
		handle_eaws
		exit "${RC}"
	fi
}

# check if a file exists
check_existing_file ()
{
	if [ -f "${CURR_FILE}" ];
	then
		MSG="<<ERROR>>    [${CURR_FILE}] already exists. remove or backup this file before continuing."
		store_eaws
		RC=1
	fi
}

# create and verify creation of directory
create_dir ()
{
	echo "<<STATUS>>   creating dir [${NEWDIR}]." >> "${LOG}"
	mkdir "${NEWDIR}"
	
	if [ ! -d "${NEWDIR}" ];
	then
		MSG="<<ERROR>>    [${NEWDIR}] could not be created."
		store_eaws
		handle_eaws
		exit 1
	fi
}

# output supplemental info after a failed write test
failedwrite_post ()
{
	ASPACE=$(df -k "${TARGETDIR}" | sed 'N;/\n \+/s/\n \+/ /;P;D' | tail -1 | awk '{print $4}')
	MSG="<<ERROR>>        - available space in [${TARGETDIR}]: $(printf "%'.f" ${ASPACE}) KB."
	store_eaws
	echo "" >> "${LOG}"
	
	echo "<<STATUS>>   ls -lt of write attempts in [${TARGETDIR}]:" >> "${LOG}"
	ls -lt "${TARGETDIR}/${SPROG}-dd-write."* &>> "${LOG}"
	echo "" >> "${LOG}"

	echo "<<STATUS>>   cleaning up filesystem [${TARGETDIR}]." >> "${LOG}"
	echo "" >> "${LOG}"
	
	# remove all dd files from target directory
	rm -f "${TARGETDIR}/${SPROG}-dd-"* >/dev/null 2>&1
}

# output initial failed write test message
failedwrite_pre ()
{
	echo "" >> "${LOG}"
	MSG="<<ERROR>>    failed to execute write test successfully."
	store_eaws
	RC=1
}

# print 'log-only' errors and warnings only to log
print_lo_eaws()
{
	echo "           ---- LOG-ONLY ----" >> "${LOG}"
	for LO_EAW in "${LO_EAWS[@]}";
	do
		echo "${LO_EAW}" >> "${LOG}"
	done
}

# print errors and warnings
print_eaws()
{
	if [ "${LO_EAWS}" ];
	then
		print_lo_eaws
		echo "         ---- ALL REMAINING ----" >> "${LOG}"
	fi

	# print errors and warnings to console and log
	for EAW in "${EAWS[@]}";
	do
		echo "${EAW}" | tee -a ${FILES} 2>/dev/null
	done 
}

# organize which errors and warnings to print and to where
handle_eaws ()
{
	if [ "${EAWS}" ];
	then
		echo "" | tee -a ${FILES} 2>/dev/null
		echo "********* ALL ERRORS & WARNINGS *********" | tee -a ${FILES} 2>/dev/null
		print_eaws
		echo "*****************************************" | tee -a ${FILES} 2>/dev/null
		echo "" | tee -a ${FILES} 2>/dev/null
	elif [ "${LO_EAWS}" ];
	then
		echo "" >> "${LOG}"
		echo "********* ALL ERRORS & WARNINGS *********" >> "${LOG}"
		print_lo_eaws
		echo "*****************************************" >> "${LOG}"
		echo "" >> "${LOG}"
	fi
}

# store errors and warnings;
#    print to log
store_eaws ()
{
	if [ "${LO}" -eq 0 ];
	then
		EAWS+=("${MSG}")
	else
		LO_EAWS+=("${MSG}")
	fi

	if [ "${LOG}" ];
	then
		echo "${MSG}" >> "${LOG}"
	fi

	LO=0
}

# ====================================================================
# FUNCTIONS
# ====================================================================

# clean up output directory
cleanup ()
{
	# NOCLEAN: do not delete output dirs from previous runs
	if [ "${NOCLEAN}" -eq 0 ] && [ -d "${OUTPUT}" ];
	then
		rm -rf "${OUTPUT}" >/dev/null 2>&1

		# verify directory was deleted
		if [ -d "${OUTPUT}" ];
		then
			echo "<<ERROR>>    unable to cleanup [${OUTPUT}]."
		fi
	fi
}

# compress all files
tar_files ()
{
	cd "${BASEDIR}"
	tar -zcf "${TARFILE}" "./${SPROG}_output" "./${SPROG}.results" "./${SPROG}.log" "./${PROG}" 2>&1

	# verify that the gather_info tar.gz was created successfully
	if [ ! -f "${TARFILE}" ];
	then
		echo "<<ERROR>>    unable to create [${TARFILE}]."
		echo "<<ERROR>>        manually compress or delete [${OUTPUT}]."
		echo ""
		exit 1
	fi
}

# print results of run
print_results ()
{
	echo "--" >> "${LOG}"
	> "${SPROG_FULL}.real.${ITERATIONS}"
	egrep -i "real" "${RESULTS_DIR}/k8s_iotest-"*out* | tee "${SPROG_FULL}.real.${ITERATIONS}" | tee -a "${LOG}" >/dev/null
	echo "--" >> "${LOG}"
	echo "" >> "${LOG}"
	echo "<<STATUS>>   creating results file: [${RESULTS}]" >> "${LOG}"
	
	# create results file and add to output files list
	echo "" > "${RESULTS}"
	FILES="${FILES} ${RESULTS}"
	
	# clean up dd output files
	rm -f "${TARGETDIR}/${SPROG}-dd-"* >/dev/null 2>&1
	
	# calculate results
	TRR=0
	TWR=0
	while read -r RECORD
  	do
		TYPE=$(echo "${RECORD}" | awk -F\: '{ print $1 }')
		S=$(echo "${RECORD}" | awk '{ print $NF }')
		
		case "${TYPE}" in
			"${RESULTS_DIR}/k8s_iotest-read"*)	TRR=$(echo "scale=2;${TRR} + ${S}" | bc -l)
			;;
			"${RESULTS_DIR}/k8s_iotest-write"*)	TWR=$(echo "scale=2;${TWR} + ${S}" | bc -l)
			;;
		esac
  	done < "${SPROG_FULL}.real.${ITERATIONS}"
	
	FS=$(echo "${BLOCKS}*${BLOCKSIZE}*1024" | bc -l)
	MB=$(echo "scale=2;${FS} / 1024 / 1024" | bc -l)
	GB=$(echo "scale=2;${MB} / 1024" | bc -l) 
	ARR=$(echo "scale=2;${TRR} / ${ITERATIONS}" | bc -l)
	AWR=$(echo "scale=2;${TWR} / ${ITERATIONS}" | bc -l)
	ART=$(echo "scale=2;${MB} / ${ARR}" | bc -l)
	AGR=$(echo "scale=2;${ART} * ${ITERATIONS}" | bc -l)
	AWT=$(echo "scale=2;${MB} / ${AWR}" | bc -l)
	AGW=$(echo "scale=2;${AWT} * ${ITERATIONS}" | bc -l)
	
	# print results to output files and console
	echo ""  | tee -a "${LOG}"
	echo ""  | tee -a "${LOG}" >/dev/null
	echo "-----------------------------" | tee -a ${FILES} >/dev/null
	echo "RESULTS"  | tee -a ${FILES}
	echo "-------"  | tee -a ${FILES}
	echo "INVOCATION:  ${PROG} ${OPTIONS}" | tee -a ${FILES}
	echo ""  | tee -a ${FILES}
	echo "TARGET DETAILS" | tee -a ${FILES}
 	echo "  target dir:   ${TARGETDIR}" | tee -a ${FILES}
	echo "  df -kT:       ${TARGETDF}" | tee -a ${FILES}
    echo "  mount point:  ${MOUNT}" | tee -a ${FILES}
	echo "  iterations:   ${ITERATIONS}" | tee -a ${FILES}
	echo "  filesize:     $(printf "%'.2f" ${GB}) gigabytes" | tee -a ${FILES}
	echo ""  | tee -a ${FILES}
	echo "STATISTICS"  | tee -a ${FILES}
	
	echo "  read time:              $(printf "%'.2f" ${ARR}) seconds per physical core average" >> "${LOG}"
	echo "  read throughput rate:   $(printf "%'.2f" ${ART}) megabytes/second per physical core" | tee -a ${FILES}
	echo "  write time:             $(printf "%'.2f" ${AWR}) seconds per physical core average" >> "${LOG}"
	echo "  write throughput rate:  $(printf "%'.2f" ${AWT}) megabytes/second per physical core" | tee -a ${FILES}
	echo "-----------------------------" | tee -a ${FILES} >/dev/null
	
	# clean up
	rm -f "${SPROG_FULL}.real.${ITERATIONS}" >/dev/null 2>&1
	
	echo ""  | tee -a ${FILES}
	echo "" >> "${LOG}"
	echo "<<STATUS>>   processing complete." >> "${LOG}"
	echo "<<STATUS>>   compressing files and cleaning up." >> "${LOG}"
	END_TIME=$(date)
	echo "<<STATUS>>   end time: ${END_TIME}." >> "${LOG}"
	echo "" >> "${LOG}"
	echo "Start time: ${START_TIME}." >> "${LOG}"
	echo "End time:   ${END_TIME}." >> "${LOG}"
	echo "" >> "${LOG}"
}

# process dd based writes and reads
processwriteread ()
{
  	echo "<<STATUS>>   executing write testing" >> "${LOG}"
	sync
	((COUNT=0))
	while [ "${COUNT}" -lt "${ITERATIONS}" ]
		do
		((COUNT=COUNT+1))
        echo "             launching iteration: ${COUNT}" >> "${LOG}"
		(/usr/bin/time -p dd if=/dev/zero of="${TARGETDIR}/${SPROG}-dd-write.${COUNT}" bs="${BLOCKSIZE}k" count="${BLOCKS}" conv=fsync) \
		 > "${RESULTS_DIR}/k8s_iotest-writetest.out.${COUNT}" 2>&1 &
		done
	echo "             waiting for all write tests to complete" >> "${LOG}"
	wait
	
	# make sure all write files are the same size - 
	#    checks if the FS ran out of space during test
	((COUNT=1))
	while [ "${COUNT}" -lt "${ITERATIONS}" ]
	do
		SIZE1=`(ls -ltn "${TARGETDIR}/${SPROG}-dd-write.${COUNT}" | awk '{ print $5 }') 2>/dev/null`
		((COUNT=COUNT+1))
		SIZE2=`(ls -ltn "${TARGETDIR}/${SPROG}-dd-write.${COUNT}" | awk '{ print $5 }') 2>/dev/null`
		
		if [ ! "${SIZE1}" ] || [ ! "${SIZE2}" ]
	  	then
			failedwrite_pre
			
			MSG="<<ERROR>>    unable to verify sizes of output files."
			store_eaws

			((PREV_COUNT=COUNT-1))
			LO=1
			MSG="<<ERROR>>        - file size missing for iteration ${PREV_COUNT} or ${COUNT}."
			store_eaws

			failedwrite_post
			break
		elif [ "${SIZE1}" -ne "${SIZE2}" ]
		then
			failedwrite_pre

			MSG="<<ERROR>>    target filesystem [${TARGETDIR}] does not have an adequate amount of free disk space to complete the test."
			store_eaws
			
			failedwrite_post
			break
		fi
	done
	
	if [ "${RC}" -eq 0 ]
	then
		echo "<<STATUS>>   write test complete" >> "${LOG}"
		sync
		echo "<<STATUS>>   current time: $(date)" >> "${LOG}"
		echo "<<STATUS>>   executing read testing" >> "${LOG}"
		((COUNT=0))
		while [ "${COUNT}" -lt "${ITERATIONS}" ]
	  	  do
			((COUNT=COUNT+1))
			echo "             launching iteration: ${COUNT}" >> "${LOG}"
			(/usr/bin/time -p dd if="${TARGETDIR}/${SPROG}-dd-write.${COUNT}" of=/dev/null bs="${BLOCKSIZE}k" count="${BLOCKS}") \
		 	 > "${RESULTS_DIR}/k8s_iotest-readtest.out.${COUNT}" 2>&1 & 
	  	  done
		echo "             waiting for all read tests to complete" >> "${LOG}"
		wait
		echo "<<STATUS>>   read test complete" >> "${LOG}"
		echo "<<STATUS>>   current time: $(date)" >> "${LOG}"
		echo "" >> "${LOG}"
	fi
}

# validate input parameters for iterations and writeable target directory
validate_system ()
{
	# create copies of cpuinfo and meminfo; gather system
	#    specs and start calculations
	if [ -f "/proc/cpuinfo" ] && [ -f "/proc/meminfo" ];
	then
		NEWDIR="${SYSTEM_FILES}/proc"
		create_dir
		
		echo "<<STATUS>>   creating copy of [/proc/cpuinfo]." >> "${LOG}"
		cp "/proc/cpuinfo" "${NEWDIR}"
		
		echo "<<STATUS>>   creating copy of [/proc/meminfo]." >> "${LOG}"
		cp "/proc/meminfo" "${NEWDIR}"		

		# find number of sockets
		SOX=$(cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l)
		if [ "${SOX}" -eq 0 ]
		then
			MSG="<<ERROR>>    no physical CPU cores found."
			store_eaws
			RC=1
		fi

		if [ "${RC}" -eq 0 ]
		then
			echo "<<STATUS>>   beginning calculations." >> "${LOG}"
			echo "" >> "${LOG}"

			# find cores per socket and calculate # of physical cores;
			#	# of iterations = # of physical cores
			CPSOX=$(sed -n 's/^cpu cores//p' /proc/cpuinfo 2>&1 | uniq | cut -f2- -d ':' | sed -e 's/^[[:space:]]*//')
			ITERATIONS=$(echo "${SOX}*${CPSOX}" | bc -l)
			echo "Sockets: ${SOX}" >> "${LOG}"
			echo "Physical cores per socket: ${CPSOX}" >> "${LOG}"
			echo "Total physical cores: ${ITERATIONS}" >> "${LOG}"
			echo "" >> "${LOG}"

			if [ "${SOX}" -gt 2 ];
			then
				MSG="<<WARNING>>  more than two sockets detected. CPU performance may be affected by NUMA."
				store_eaws
			fi

			if [ "${ITERATIONS}" ]
			then
				# set stack size equal to total mem size;
				#    store in separate vars for reference later
				TOTMEM=$(sed -n '/MemTotal:/p' /proc/meminfo | awk '{print $2}')
				STACKSIZE=${TOTMEM}
				
				# calculate minimum required memory for k8s_iotest (cores*4GB)
				#	- actual check is for 3.8047 GB per core - allow a buffer
				#		of 200 MB per core for RAM reserved by the OS, etc
				RIO_MINMEM=$(echo "${ITERATIONS}*3989504" | bc -l)

				# calculate minimum required memory for SAS (cores*8GB)
				#	- actual check is for 7.8047 GB per core - allow a buffer
				#		of 200 MB per core for RAM reserved by the OS, etc
				SAS_MINMEM=$(echo "${ITERATIONS}*8183808" | bc -l)

				echo "Minimum required memory for ${PROG} (4 GB/core): $(printf "%'.f" ${RIO_MINMEM}) KB" >> "${LOG}"
				echo "Minimum required memory for SAS (8 GB/core): $(printf "%'.f" ${SAS_MINMEM}) KB" >> "${LOG}"
				echo "Total memory: $(printf "%'.f" ${TOTMEM}) KB" >> "${LOG}"
				echo "" >> "${LOG}"
				
				# check if the machine meets the minimum memory requirements
				if [ "${TOTMEM}" -lt "${RIO_MINMEM}" ]
				then
					MSG="<<ERROR>>    the ${PROG} minimum requirement of 4 GB RAM per physical core is not met."
					store_eaws
					MSG="<<ERROR>>        - ${ITERATIONS} physical cores and $(printf "%'.f" ${TOTMEM}) KB RAM are present."
					store_eaws
					RC=1
				elif [ "${TOTMEM}" -lt "${SAS_MINMEM}" ]
				then
					LO=1
					MSG="<<WARNING>>  the SAS minimum requirement of 8 GB RAM per physical core is not met."
					store_eaws
					LO=1
					MSG="<<WARNING>>      - ${ITERATIONS} physical cores and $(printf "%'.f" ${TOTMEM}) KB RAM are present."
					store_eaws
					echo "" >> "${LOG}"
				fi
			else
				MSG="<<ERROR>>    unable to calculate iteration count."
				store_eaws
				RC=1
			fi
		fi
	else
		echo "" >> "${LOG}"

		if [ ! -f "/proc/cpuinfo" ];
		then
			MSG="<<ERROR>>    [/proc/cpuinfo] does not exist."
			store_eaws
		fi
		
		if [ ! -f "/proc/meminfo" ];
		then
			MSG="<<ERROR>>    [/proc/meminfo] does not exist."
			store_eaws
		fi
		
		RC=1
	fi
	
	# make sure target directory is writeable and dd
	#   can be run without issues
	if [ -d  "${TARGETDIR}" ]
  	then
  		TMPFILE="${TARGETDIR}/tmpfile."$$
		touch "${TMPFILE}" >/dev/null 2>&1 
		if [ $? -ne 0 ]
  		then
			MSG="<<ERROR>>    target directory not writeable."
			store_eaws
			RC=2
		else
			dd if=/dev/zero of=/dev/null bs=1k count=1 2>"${TMPFILE}"
			if [ $? -ne 0 ]
	  		then
				MSG="<<ERROR>>    cannot execute 'dd' command."
				store_eaws
				cat "${TMPFILE}"
				RC=1
			fi
		fi
		rm -f "${TMPFILE}" >/dev/null 2>&1
	else
		MSG="<<ERROR>>    target directory does not exist."
		store_eaws
		RC=2
	fi
	
	# check if xfs file system and calculate allocation buffer if so
	#
	# ASC
	# 0 -> skip
	# 1 -> user-defined
	# 2 -> calculated
	if [ "${RC}" -eq 0 ];
	then
		# store the target dir's mount info
		TARGETDF=$(df -k "${TARGETDIR}" | sed 'N;/\n \+/s/\n \+/ /;P;D' | tail -1)
		MP=$(echo "${TARGETDF}" | awk '{print $NF}')
		MOUNT=$(mount | grep -F "on ${MP} " )

		if [ "${MOUNT}" ];
		then
			# get the file system type
			FSTYPE=$(echo "${MOUNT}" | awk '{print $5}')

			if [ "${FSTYPE}" ];
			then
				echo "File system type: ${FSTYPE}" >> "${LOG}"
				
				# xfs requires special preallocation buffer calculations
				if [ "${FSTYPE}" = "xfs" ];
				then
					# check if allocsize was defined during mount; if so,
					#    extract units and size then normalize
					FAS=$(echo "${MOUNT}" | sed -rn 's/.*allocsize=([^,]+).*/\1/p')

					if [ "${FAS}" ];
					then
						echo "Mount-defined preallocation size: ${FAS}" >> "${LOG}"
						AS=$(echo "${FAS}" | sed -rn 's/([0-9]+)[a-zA-Z]+/\1/p')
						UNIT=$(echo "${FAS}" | sed -rn 's/[0-9]+([a-zA-Z]+)/\1/p')

						case "${UNIT}" in
							G|GB|g|gb|gB|GiB|gib|giB|Gib)
								FACTOR=1048576
							;;
							M|MB|m|mb|mB|MiB|mib|miB|Mib)
								FACTOR=1024
							;;
							K|KB|k|kb|kB|KiB|kib|kiB|Kib)
								FACTOR=1
							;;
						esac
					fi

					if [ "${FACTOR}" ];
					then
						MAS=$(echo "${AS}*${FACTOR}" | bc -l)
						ASC=1
					else
						if [ "${FAS}" ];
						then
							MSG="<<WARNING>>  cannot find units for XFS preallocation size. calculating max possible size."
							store_eaws
						fi

						# max allocsize = (file size | 8GB), whichever is smaller
						if [ "${STACKSIZE}" -le 8388608 ];
						then
							MAS=${STACKSIZE}
						else
							MAS=8388608
						fi

						ASC=2
					fi

					# calculate the max total allocsize for all iterations
					if [ "${MAS}" ];
					then
						echo "Max preallocation size per file: $(printf "%'.f" ${MAS}) KB" >> "${LOG}"
						TAS=$(echo "${MAS}*${ITERATIONS}" | bc -l)
						echo "Max total preallocation size: $(printf "%'.f" ${TAS}) KB" >> "${LOG}"
					else
						MAS=0
						ASC=0
						MSG="<<WARNING>>  unable to calculate XFS preallocation buffer. skipping calculation."
						store_eaws
					fi
				fi
			else
				MSG="<<WARNING>>  unable to find file system type for [${TARGETDIR}]."
				store_eaws
				RC=1
			fi
		else
			MSG="<<WARNING>>  unable to find mount point for [${TARGETDIR}]."
			store_eaws
			RC=1
		fi

		if [ "${RC}" -eq 0 ];
		then
			# calculate total required space
			RESPACE=$(echo "(${STACKSIZE}+${MAS})*${ITERATIONS}" | bc -l)
			
			# get targetdir available space minus 10% total space buffer
			TSPACE=$(echo "${TARGETDF}" | awk '{print $2}')
			ASPACE=$(echo "${TARGETDF}" | awk '{print $4}')
			BUFFER=$(echo "scale=0; ${TSPACE}/10" | bc -l)
			TARGETSIZE=$(echo "scale=0; ${ASPACE}-${BUFFER}" | bc -l)
			
			# calculate # of blocks to use (total mem/blocksize);
			#    default blocksize=64k
			BLOCKS=$(echo "scale=0; ${STACKSIZE}/${BLOCKSIZE}" | bc -l)
			
			echo "" >> "${LOG}"
			echo "Blocksize: ${BLOCKSIZE} KB" >> "${LOG}"
			echo "Blocks: $(printf "%'.f" ${BLOCKS})" >> "${LOG}"
			echo "Stack size: $(printf "%'.f" ${STACKSIZE}) KB" >> "${LOG}"
			echo "Iterations: ${ITERATIONS}" >> "${LOG}"
			echo "Required space: $(printf "%'.f" ${RESPACE}) KB" >> "${LOG}"
			echo "" >> "${LOG}"
			echo "Target dir: ${TARGETDIR}" >> "${LOG}"
			echo "Total space: $(printf "%'.f" ${TSPACE}) KB" >> "${LOG}"
			echo "Available space: $(printf "%'.f" ${ASPACE}) KB" >> "${LOG}"
			echo "Buffer: $(printf "%'.f" ${BUFFER}) KB" >> "${LOG}"
			echo "Available space - buffer: $(printf "%'.f" ${TARGETSIZE}) KB" >> "${LOG}"
			echo "" >> "${LOG}"

			# check if available space - buff is less than the required space
			if [ "${TARGETSIZE}" -lt "${RESPACE}" ]
			then
				# make sure available space - buff is gt 0
				if [ "${TARGETSIZE}" -lt 1 ];
				then
					MSG="<<ERROR>>    available space - buffer is less than 1 KB in [${TARGETDIR}]."
					store_eaws
					RC=1
				else
					# recalculate file sizes to adjust for limited available space
					MSG="<<WARNING>>  insufficient free space in [${TARGETDIR}] for FULL test. smaller file sizes will be used."
					store_eaws
					echo "<<STATUS>>   recalculating stack size and # of blocks." >> "${LOG}"

					# ASC
					# 0 -> skip
					# 1 -> user-defined
					# 2 -> calculated
					if [ "${ASC}" -eq 1 ];
					then
						# use user-defined preallocation size
						STACKSIZE=$(echo "scale=0; (${TARGETSIZE}/${ITERATIONS})-${MAS}" | bc -l)
					elif [ "${ASC}" -eq 2 ];
					then
						TMP_STACKSIZE=$(echo "scale=0; ${TARGETSIZE}/${ITERATIONS}" | bc -l)

						# if stack size is lt 16GB, set max preallocation size equal to file size
						# else set max preallocation size to 8GB
						if [ "${TMP_STACKSIZE}" -le 16777216 ];
						then
							STACKSIZE=$(echo "scale=0; ${TMP_STACKSIZE}/2" | bc -l)
							MAS=$(echo "scale=0; ${TMP_STACKSIZE}-${STACKSIZE}" | bc -l)
						else
							MAS=8388608
							STACKSIZE=$(echo "scale=0; ${TMP_STACKSIZE}-${MAS}" | bc -l)
						fi
					else
						STACKSIZE=$(echo "scale=0; ${TARGETSIZE}/${ITERATIONS}" | bc -l)
					fi

					BLOCKS=$(echo "scale=0; ${STACKSIZE}/${BLOCKSIZE}" | bc -l)
					
					# recalculate to adjust for rounding
					STACKSIZE=$(echo "${BLOCKS}*${BLOCKSIZE}" | bc -l)
					RESPACE=$(echo "(${STACKSIZE}+${MAS})*${ITERATIONS}" | bc -l)
					TOT_STACKSIZE=$(echo "${STACKSIZE}*${ITERATIONS}" | bc -l)

					LO=1
					MSG="<<WARNING>>  file sizes are smaller than RAM."
					store_eaws

					# if sum of all file sizes is less than RAM,
					#    notify user of potential caching
					if [ "${TOT_STACKSIZE}" -le "${TOTMEM}" ];
					then
						MSG="<<WARNING>>  potential caching involved. use WRITES only."
						store_eaws
					fi

					echo "" >> "${LOG}"
					echo "Recalculated Sizes" >> "${LOG}"
					echo "------------------" >> "${LOG}"
					echo "Blocksize: ${BLOCKSIZE} KB" >> "${LOG}"
					echo "Blocks: $(printf "%'.f" ${BLOCKS})" >> "${LOG}"
					echo "Stack size: $(printf "%'.f" ${STACKSIZE}) KB" >> "${LOG}"
					echo "Iterations: ${ITERATIONS}" >> "${LOG}"
					
					if [ "${MAS}" -gt 0 ];
					then
						echo "Max preallocation size per file: $(printf "%'.f" ${MAS}) KB" >> "${LOG}"
					fi
					
					echo "Required space: $(printf "%'.f" ${RESPACE}) KB" >> "${LOG}"
					echo "" >> "${LOG}"
				fi
			fi
			
			# verify that blocks and blocksize are all set before starting tests
			if [ -z "${BLOCKS}" ];
			then
				MSG="<<ERROR>>    block count not calculated correctly."
				store_eaws
				RC=1
			fi
			if [ -z "${BLOCKSIZE}" ];
			then
				MSG="<<ERROR>>    block size not calculated correctly."
				store_eaws
				RC=1
			fi

			echo "<<STATUS>>   calculations complete." >> "${LOG}"
			echo "<<STATUS>>   current time: $(date)" >> "${LOG}"
		fi
	fi
}

initialize ()
{
	# get fqdn - get short hostname if unable to get fqdn
	FHOST=`(hostname -f || cat /etc/hostname) 2>/dev/null`
	SHOST=$(hostname -s 2>/dev/null)

	if [ ! "${SHOST}" ] && ( [ ! "${FHOST}" ] || [[ "${FHOST}" == "hostname: Name or service not known" ]] );
	then
		echo ""
		echo "<<ERROR>>    unable to find hostname. exiting..."
		echo ""
		exit 1
	elif [ "${SHOST}" ] && ( [ ! "${FHOST}" ] || [[ "${FHOST}" == "hostname: Name or service not known" ]] );
	then
		FHOST="${SHOST}"
	elif [ ! "${SHOST}" ];
	then
		SHOST="${FHOST}"
	fi

	SPROG="k8s_iotest_${SHOST}_${DATETIME}"
	SPROG_FULL="${BASEDIR}/${SPROG}"
	OUTPUT="${SPROG_FULL}_output"
	SYSTEM_FILES="${OUTPUT}/system_files"
	RESULTS_DIR="${OUTPUT}/results"
	RESULTS="${SPROG_FULL}.results"

	# verify that an output tar does not exist from today
	CURR_FILE="${SPROG_FULL}.tar"
	check_existing_file
	
	# verify that an output tar.gz does not exist from today
	TARFILE="${SPROG_FULL}.tar.gz"
	CURR_FILE="${TARFILE}"
	check_existing_file

	if [ -d "${OUTPUT}" ];
	then
		MSG="<<ERROR>>    [${OUTPUT}] already exists. remove or backup this directory before continuing."
		store_eaws
		RC=1
		NOCLEAN=1
	fi
	
	if [ "${RC}" -eq 0 ];
	then
		LOG="${SPROG_FULL}.log"
		FILES="${LOG}"
		> "${LOG}"

		# check the container OS we're running on
		OS_RELEASE="/etc/os-release"

		if [ -f "${OS_RELEASE}" ];
		then
			set -a
			source "${OS_RELEASE}"
			set +a

			# get the major release version
			OS_FULL="${PRETTY_NAME}"
		else
			echo ""
			echo "<<ERROR>>    operating system not supported. exiting..." | tee -a "${LOG}"
			echo ""
			exit 1
		fi

		# validate that all required commands exist
		check_commands
		
		echo "${SCRIPT_NAME}" > "${LOG}"
		echo "-----------" >> "${LOG}"
		echo "Hostname: ${FHOST}" >> "${LOG}"
		echo "Date: ${DATE}" >> "${LOG}"
		echo "Script Name: ${PROG}" >> "${LOG}"
		echo "Script Version: ${SCRIPT_VERSION}" >> "${LOG}"
		echo "Script Build: ${SCRIPT_BUILD_ID}" >> "${LOG}"
		echo "Script Invocation: ${PROG} ${OPTIONS}" >> "${LOG}"
		echo "OS: ${OS_FULL}" >> "${LOG}"
		echo "" >> "${LOG}"
		echo "<<STATUS>>   start time: ${START_TIME}." >> "${LOG}"

		# create 'output' dir and 'system_files' & 'results' subdirs
		NEWDIR="${OUTPUT}"
		create_dir

		NEWDIR="${RESULTS_DIR}"
		create_dir

		NEWDIR="${SYSTEM_FILES}"
		create_dir
		
		validate_system
	fi
}

# ====================================================================
# SCRIPT START
# ====================================================================
export LANG=en_US

# count command line options
if [ $# -eq 0 ]; then
	usage
    exit 1
fi

# validate command line options
while [[ $# -gt 0 ]]
do
OPT="$1"

case "${OPT}" in
	--help|-help|--h|-h)
		usage
		exit 0
	;;
	--version|-version|--v|-v)
		version
		exit 0
	;;
	-t)
		if [ -z "$2" ];
		then
			echo ""
			echo "Option $1 requires an argument."
			echo ""
			exit 2
		elif [[ "$2" != /* ]];
		then
			echo ""
			echo "Invalid path: $2"
			usage
			exit 2
		fi
		
		TARGETDIR="$2"

		if [[ "${TARGETDIR}" != "/" ]];
		then
			TARGETDIR=${TARGETDIR%/}
		fi
		shift
	;; 
	*)
		echo ""
		echo "Invalid option: $1"
		usage
		exit 2
	;;
esac
shift
done

initialize

if [ "${RC}" -eq 0 ]
then
	echo -e "\nPerforming iotest with ${ITERATIONS} iterations against the '${MP}' file system..."
	processwriteread

	if [ "${RC}" -eq 0 ]
	then
		print_results
	fi

	handle_eaws

	if [ "${RC}" -eq 0 ]
	then
		tar_files
	fi
else
	handle_eaws

	if [ "${RC}" -eq 2 ]
	then
		usage
	fi
fi

cleanup

exit "${RC}"

