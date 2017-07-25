#!/bin/bash

LOGFILE_DIR=/var/log
NAGIOS_LOG=$LOGFILE_DIR/xenBackupNagios.inf
LAST_RUN_FILE=$LOGFILE_DIR/xenBackup.last
DATE_NOW=`date +%s`
TIME_NOT_STARTED_TRESHOLD=86400

#LOG=/root/nagiosConnect.log
RUNNING=0

########################################


if [ -f $NAGIOS_LOG ] && [ -f $LAST_RUN ]; then
        PID=$(sed '1q;d' $NAGIOS_LOG)
        if [ -f /proc/$PID/status ]; then
                RUNNING=1
        else
                RUNNING=0
        fi
elif [ ! -f $NAGIOS_LOG ] && [ -f $LAST_RUN ]; then
        echo "OK backup script finished without errors | running=0"
        exit 0
fi

if [ ! -f $LAST_RUN ]; then
        echo "CRITICAL last run file $LAST_RUN not found" >> $LOG
        exit 2
else
        LAST_RUN_TIME=$(sed '1q;d' $LAST_RUN_FILE)
        TIME_NOT_STARTED=$(( $DATE_NOW - $LAST_RUN_TIME ))
        if [ $TIME_NOT_STARTED -gt $TIME_NOT_STARTED_TRESHOLD ] && [ $RUNNING -eq 0 ]; then
                echo "CRITICAL script has not started more than $TIME_NOT_STARTED"
                exit 2
        fi
fi

if [ -f $NAGIOS_LOG ] && [ $RUNNING -eq 0 ]; then
        echo "WARNING backup script finished with errors | running=0"
        exit 1
fi

if [ -f $NAGIOS_LOG ] && [ $RUNNING -eq 1 ]; then
        echo "OK backup script is running | running=1"
        exit 0
fi
