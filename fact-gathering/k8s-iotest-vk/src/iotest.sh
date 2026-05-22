# print usage
usage ()
{
        echo ""
        echo "<<USAGE>>  ${PROG} -i <iterations> -t <target filesystem> -b <block count> -s <block size>"
        echo ""
        echo "  function run current dd write and read tests to a SAS filesystem to test thruput"
        echo "           where results will be stored in ${PROG}.results.<iterations>"
        echo ""
        echo "  where    iterations are the number of concurrent tests to run"
        echo "           target filesystem is the SAS read/write filesystem to test"
        echo "           block count is the number of block you want dd to process (eg: 20000)"
        echo "           block size is the size of the blocks you want dd to process in K (eg: 64)"
}
# validate input parameters for iterations and writeable target directory
validateinput ()
{
        UNAME=`uname`
        TMPNAME=tmpfile.$$
        TMPFILE=${TARGETDIR}/${TMPNAME}
        rm -f ${PROG}-readtest.out.* ${PROG}-writetest.out.* >/dev/null 2>&1
        if [ -z "${ITERATIONS}" ]
          then  echo "<<ERROR>>  iteration count not provided"
                RC=1
        fi
        if [  ! -d  "${TARGETDIR}" ]
          then  echo "<<ERROR>>  target directory not provided or does not exist"
                RC=1
          else  touch ${TMPFILE} >/dev/null 2>&1 
                if [ $? -ne 0 ]
                  then  echo "<<ERROR>>  target directory not writeable"
                        RC=1
                  else  dd if=/dev/zero of=/dev/null bs=1k count=1 2>${TMPFILE}
                        if [ $? -ne 0 ]
                          then  echo "<<ERROR>> cannot execute dd command"
                                cat ${TMPFILE}
                                rm -f ${TMPFILE} >/dev/null 2>&1
                                RC=1
                        fi
                fi
                rm -f ${TMPFILE} >/dev/null 2>&1
        fi
        if [ -z "${BLOCKS}" ]
          then  echo "<<ERROR>>  block count not provided"
                RC=1
        fi
        if [ -z "${BLOCKSIZE}" ]
          then  echo "<<ERROR>>  block size not provided"
                RC=1
        fi
}
# process dd based writes and reads
processwriteread ()
{
        echo "<<STATUS>> executing write testing"
        sync
        ((COUNT=0))
        while [ ${COUNT} -lt ${ITERATIONS} ]
          do
                ((COUNT=COUNT+1))
                echo "           launching iteration: ${COUNT}"
                (/usr/bin/time -p dd if=/dev/zero of=${TARGETDIR}/${PROG}-dd-write.${COUNT} bs=${BLOCKSIZE}k count=${BLOCKS}) > ${PROG}-writetest.out.${COUNT} 2>&1 & 
          done
        echo "           waiting for all write tests to complete"
        wait 
        ((COUNT=1))
        while [ ${COUNT} -lt ${ITERATIONS} ]
          do
                SIZE1=`ls -lt ${TARGETDIR}/${PROG}-dd-write.${COUNT} | awk '{ print $5 }'`
                ((COUNT=COUNT+1))
                SIZE2=`ls -lt ${TARGETDIR}/${PROG}-dd-write.${COUNT} | awk '{ print $5 }'`
                if [ ${SIZE1} -ne ${SIZE2} ]
                  then  echo ""
                        echo "<<STATUS>> target filesystem [${TARGETDIR}] does not have an adequate amount of free disk space to complete the test"
                        echo ""
                        echo "<<STATUS>> results of df on target filesystem [${TARGETDIR}]"
                        echo ""
                        df ${TARGETDIR}
                        echo ""
                        echo ""
                        echo "<<STATUS>> file size of write attempts"
                        echo ""
                        ls -lt ${TARGETDIR}/${PROG}-dd-write.*
                        echo ""
                        echo ""
                        echo "<<STATUS>> cleaning up filesystem [${TARGETDIR}]"
                        echo ""
                        echo "<<ERROR>> ${PROG}: failed to execute write test successfully"
                        rm -f ${TARGETDIR}/${PROG}-dd-* >/dev/null 2>&1
                        RC=1
                        break
                fi
          done
        if [ ${RC} -eq 0 ]
          then  echo "           write test complete"
                echo "<<STATUS>> executing read testing"
                sync
                ((COUNT=0))
                while [ ${COUNT} -lt ${ITERATIONS} ]
                  do
                        ((COUNT=COUNT+1))
                        echo "           launching iteration: ${COUNT}"
                        (/usr/bin/time -p dd if=${TARGETDIR}/${PROG}-dd-write.${COUNT} of=/dev/null bs=${BLOCKSIZE}k count=${BLOCKS}) \
                         > ${PROG}-readtest.out.${COUNT} 2>&1 & 
                  done
                echo "           waiting for all read tests to complete"
                wait
                echo "           read test complete"
        fi
}
# create output file and cleanup
cleanup ()
{
        echo "<<STATUS>> creating file: ${PROG}.results.${ITERATIONS} with results"
        #egrep -i "real" ${PROG}-*out* > ${PROG}.results.${ITERATIONS}
        grep -i "real" ${PROG}-*out* > ${PROG}.results.${ITERATIONS}
        rm -f ${TARGETDIR}/${PROG}-dd-* >/dev/null 2>&1
        TRR=0
        TWR=0
        while read RECORD
          do
                TYPE=`echo ${RECORD} | awk -F\: '{ print $1 }'`
                case "${UNAME}" in
                 HP-UX) TIME=`echo ${RECORD} | awk '{ print $NF }'`
                        COUNT=`echo ${TIME} | awk -F\: '{ print NF }'`
                        if [ ${COUNT} -eq 3 ]
                          then  H=`echo ${TIME} | awk -F\: '{ print $1*60*60 }'`
                                M=`echo ${TIME} | awk -F\: '{ print $2*60 }'`
                                S=`echo ${TIME} | awk -F\: '{ print $3 }'` 
                          else  H=0
                                if [ ${COUNT} -eq 2 ]
                                  then  M=`echo ${TIME} | awk -F\: '{ print $1*60 }'`
                                        S=`echo ${TIME} | awk -F\: '{ print $2 }'` 
                                  else  M=0
                                        S=`echo ${TIME} | awk '{ print $1 }'` 
                                fi
                        fi
                        S=`echo "scale=2;${S} + ${M} + ${H}" | bc -l`
                        ;;
                 *)     S=`echo ${RECORD} | awk '{ print $NF }'`
                        ;;
                esac
                case ${TYPE} in
                  ${PROG}-read*)        TRR=`echo "scale=2;${TRR} + ${S}" | bc -l`
                                        ;;
                  ${PROG}-write*)       TWR=`echo "scale=2;${TWR} + ${S}" | bc -l`
                                        ;;
                esac
          done < ${PROG}.results.${ITERATIONS}
        #((FS=BLOCKS*BLOCKSIZE*1024))
        FS=`echo "${BLOCKS}*${BLOCKSIZE}*1024" | bc -l`
        MB=`echo "scale=2;${FS} / 1024 / 1024" | bc -l` 
        ARR=`echo "scale=2;${TRR} / ${ITERATIONS}" | bc -l`
        AWR=`echo "scale=2;${TWR} / ${ITERATIONS}" | bc -l`
        ART=`echo "scale=2;${MB} / ${ARR}" | bc -l`
        AGR=`echo "scale=2;${ART} * ${ITERATIONS}" | bc -l`
        AWT=`echo "scale=2;${MB} / ${AWR}" | bc -l`
        AGW=`echo "scale=2;${AWT} * ${ITERATIONS}" | bc -l`
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        #echo "RESULTS"  | tee -a ${PROG}.results.${ITERATIONS}
        echo "RESULTS"  | tee ${PROG}.results.${ITERATIONS}
        echo "-------"  | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo "INVOCATION            : ${PROG} ${OPTIONS}" | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo "TARGET DETAILS" | tee -a ${PROG}.results.${ITERATIONS}
        echo "  directory           : ${TARGETDIR}" | tee -a ${PROG}.results.${ITERATIONS}
        case "${UNAME}" in
           AIX)         echo "  df                  : `df -P ${TARGETDIR} 2>/dev/null | tail -1`" | tee -a ${PROG}.results.${ITERATIONS}
                        MP=`df -P ${TARGETDIR} 2>/dev/null | tail -1 | awk '{ print $NF }'`
                        echo "  mount point         :" `/usr/sbin/mount 2>/dev/null | grep ${MP} 2>/dev/null | tail -1 | sed "s;        ;;g"` | tee -a ${PROG}.results.${ITERATIONS}
                        ;;
          HP-UX)        MP=`df -P ${TARGETDIR} 2>/dev/null | awk '{ print $NF }' | tail -1`
                        echo "  mount point         : `/sbin/mount 2>/dev/null | grep ${MP} 2>/dev/null | tail -1`" | tee -a ${PROG}.results.${ITERATIONS}
                        ;;
          SunOS)        echo "  df                  : `df ${TARGETDIR} 2>/dev/null | tail -1`" | tee -a ${PROG}.results.${ITERATIONS}
                        MP=`df ${TARGETDIR} 2>/dev/null | tail -1 | awk '{ print $NF }'`
                        echo "  mount point         : `/usr/sbin/mount 2>/dev/null | grep ${MP} 2>/dev/null | tail -1`" | tee -a ${PROG}.results.${ITERATIONS}
                        ;;
          Linux)        echo "  df                  : `df  -P ${TARGETDIR} 2>/dev/null | tail -1`" | tee -a ${PROG}.results.${ITERATIONS}
                        MP=`df -P ${TARGETDIR} 2>/dev/null | tail -1 | awk '{ print $NF }'`
                        echo "  mount point         : `/bin/mount 2>/dev/null | grep ${MP} 2>/dev/null | tail -1`" | tee -a ${PROG}.results.${ITERATIONS}
                        ;;
        esac
        echo "  filesize            : ${FS} bytes or ${MB} megabytes" | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo "STATISTICS"  | tee -a ${PROG}.results.${ITERATIONS}
        printf '%36s %8s %20s\n' "  average read time in seconds     :" "${ARR}" "                    " | tee -a ${PROG}.results.${ITERATIONS}
        printf '%36s %8s %20s\n' "  average read throughput rate     :" "${ART}" "megabytes per second" | tee -a ${PROG}.results.${ITERATIONS}
        #printf '%36s %8s %20s\n' "  aggregate read throughput rate   :" "${AGR}" "megabytes per second" | tee -a ${PROG}.results.${ITERATIONS}
        printf '%36s %8s %20s\n' "  average write time in seconds    :" "${AWR}" "                    " | tee -a ${PROG}.results.${ITERATIONS}
        printf '%36s %8s %20s\n' "  average write throughput rate    :" "${AWT}" "megabytes per second" | tee -a ${PROG}.results.${ITERATIONS}
        #printf '%36s %8s %20s\n' "  aggregate write throughput rate  :" "${AGW}" "megabytes per second" | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo ""  | tee -a ${PROG}.results.${ITERATIONS}
        echo "<<STATUS>> processing complete"
}
# main
RC=0
PROG=${0##*/}
export LANG=en_US
OPTIONS=${*}
while getopts ":i:t:b:s:" opt
  do
        case $opt in
          i)    ITERATIONS=${OPTARG}
                ;; 
          t)    TARGETDIR=${OPTARG}
                ;; 
          b)    BLOCKS=${OPTARG}
                ;; 
          s)    BLOCKSIZE=${OPTARG}
                ;; 
          \?)   echo "<<ERROR>> Invalid option: -$OPTARG" >&2
                RC=1
                ;;
          :)    echo "<<ERROR>> Option -$OPTARG requires an argument." >&2
                RC=1
                ;;
        esac
  done
validateinput
if [ ${RC} -eq 0 ]
  then  processwriteread
        if [ ${RC} -eq 0 ]
          then  cleanup
        fi
  else  usage
fi
exit ${RC}