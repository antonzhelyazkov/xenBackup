#!/bin/bash

tsNow=$(date +%s)
timeNotStartedTreshold=20000

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

zimbraScriptName="zimbraSnapshot.sh"
########################################

USAGE="Usage: $(basename $0) [-h] [-n nagios log] [-l lar run]\n
        -n [FILE] Path to nagios log - zimbraSnapshot.log.\n
        -l [FILE] Lastrun file.\n
        Please use full paths!
"

if [ "$1" == "-h" ] || [ "$1" == "" ] || [ "$#" != 4 ]; then
        echo -e $USAGE
        exit $STATE_UNKNOWN
fi

while getopts n:l: option
do
        case "${option}"
                in
                n) nagiosLog=${OPTARG};;
                l) lastRun=${OPTARG};;
        esac
done

if [ ! -f $lastRun ] && [ ! -f $nagiosLog ]; then
        echo "Last run file $lastRun and Nagios inf $nagiosLog not found! This may be first run of $zimbraScriptName or sometning is wrong"
        exit $STATE_UNKNOWN
fi

if [ -f $nagiosLog ]; then
        pidNumber=$(sed '1q;d' $nagiosLog)
        if [ -f /proc/$pidNumber/status ]; then
                echo "OK $zimbraScriptName is running | running=1"
                exit $STATE_OK
        else
                echo "WARNING $zimbraScriptName is NOT running and INF $nagiosLog exists | running=0"
                exit $STATE_WARNING
        fi
fi

if [ -f $lastRun ] && [ ! -f $nagiosLog ]; then
        lastRunTS=$(sed '1q;d' $lastRun)
        if [ $(($lastRunTS + $timeNotStartedTreshold)) -lt $tsNow ]; then
                echo "WARNING backup script not started more than $(($tsNow - $lastRunTS)) | running=0"
                exit $STATE_WARNING
        else
                echo "OK backup finished without errors $(($tsNow - $lastRunTS)) seconds ago | running=0"
                exit $STATE_OK
        fi
fi
