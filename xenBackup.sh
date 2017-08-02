#!/bin/bash
#
# Written By: Anton Antonov
# Created date: Jul 25 2017
# Version: 1.0.2
#

verbose=1
DATE=`date +%Y%m%d%H%M%S`
DATE_TS=`date +%s`
XSNAME=`echo $HOSTNAME`
UUIDFILE=/tmp/xen-uuids.txt
WANTED_UUIDS=/tmp/xen-uuids-wanted.txt
NFS_SERVER_IP="10.10.10.10"
MOUNTPOINT=/mnt/backup
FILE_LOCATION_ON_NFS="/mnt/store/nfs/"
scriptLog=/var/log/xenBackup.log
nagiosLog=/var/log/xenBackupNagios.inf
LAST_RUN=/var/log/xenBackup.last

KEEP_BACKUP_DAYS=4
BACKUP_DAYS=`date +%Y%m%d%H%M%S -d "$KEEP_BACKUP_DAYS day ago"`

### Functions ###

function logPrint() {
logMessage=$1

if [ -z $2 ]; then
        nagios=0
else
        if [[  $2 =~ ^[0-1]{1}$ ]]; then
                nagios=$2
        else
                nagios=0
        fi
fi

if [ -z $3 ]; then
        exitCommand=0
else
        if [[  $3 =~ ^[0-1]{1}$ ]]; then
                exitCommand=$3
        else
                exitCommand=0
        fi
fi

echo `date` $logMessage >> $scriptLog

if [ $verbose -eq 1 ]; then
        echo $logMessage
fi

if [ $nagios -eq 1 ]; then
        echo $logMessage >> $nagiosLog
fi

if [ $exitCommand -eq 1 ]; then
        exit
fi

}

function moungNFS() {

mount ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}
EXIT_STATUS_MOUNT=$?
if [ $EXIT_STATUS_MOUNT -ne 0 ]; then
        logPrint "ERROR in mount ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}" 1 1
else
        logPrint "SUCCESS in mount ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}" 0 0
fi
}

function backup() {
UUID=$1
VMNAME=`xe vm-list uuid=$UUID | grep name-label | cut -d":" -f2 | sed 's/^ *//g'`
SNAPUUID=`xe vm-snapshot uuid=$UUID new-name-label="SNAPSHOT-$UUID-$DATE"`

xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPUUID}
TEMPLATE_STATUS=$?
if [ $TEMPLATE_STATUS -ne 0 ]; then
        logPrint "ERROR Template Problem" 1 0
fi

xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME.xva"
EXPORT_STATUS=$?
if [ $EXPORT_STATUS -ne 0 ]; then
        logPrint "ERROR Export Snapshot Problem" 1 0
fi

xe vm-uninstall uuid=${SNAPUUID} force=true
REMOVE_STATUS=$?
if [ $REMOVE_STATUS -ne 0 ]; then
        logPrint "ERROR Remove Snapshot Problem"
fi
}

### Create mount point

logPrint START 0 0

if [ -f $nagiosLog ]; then
        logPrint "file $nagiosLog exists EXIT!" 0 1
else
        echo $$ > $nagiosLog
fi

if [ -d $WANTED_UUIDS ]; then
        logPrint "ERROR file $WANTED_UUIDS exists. Something went wrong. EXIT" 1 1
fi

for UUID in "$@"
do
        echo $UUID >> $WANTED_UUIDS
done

if [ ! -d $MOUNTPOINT ]; then
        logPrint "Directory $MOUNTPOINT does NOT exist" 0 0
        mkdir -p $MOUNTPOINT
        if [ ! -d $MOUNTPOINT ]; then
                logPrint "ERROR could not create directory $MOUNTPOINT" 1 1
        else
                logPrint "Directory $MOUNTPOINT exists" 0 0
                moungNFS
        fi
else
        logPrint "Directory $MOUNTPOINT exists" 0 0
        moungNFS
fi

BACKUPPATH=${MOUNTPOINT}/${XSNAME}/${DATE}

if [ -w $MOUNTPOINT ]; then
        logPrint "Directory $MOUNTPOINT is writtable" 0 0
else
        logPrint "Directory $MOUNTPOINT is NOT writtable" 1 1
fi

mkdir -p ${BACKUPPATH}
if [ ! -d ${BACKUPPATH} ]; then
        logPrint "ERROR Directory $BACKUPPATH is does NOT exist" 1 1
fi

# Fetching list UUIDs of all VMs running on XenServer
xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | cut -d":" -f2 > ${UUIDFILE}

COUNT_UUIDFILE=$(wc -l < "${UUIDFILE}")

if [ -f $WANTED_UUIDS ]; then
        COUNT_UUIDFILE_WANTED=$(wc -l < "${WANTED_UUIDS}")
fi

if [ -z $COUNT_UUIDFILE ]; then
        ERR_MSG="ERROR No VMs found"
        logPrint "ERROR No VMs found" 1 1
fi

if [ -z $COUNT_UUIDFILE_WANTED ]; then
        logPrint "backup all VMs" 0 0
        while read VMUUID
        do
                logPrint "Working on $VMUUID" 0 0
                backup $VMUUID
        done < ${UUIDFILE}
else
        while read VMUUID
        do
                if grep -Fq "$VMUUID" ${UUIDFILE} ; then
                        logPrint "Working on $VMUUID" 0 0
                        backup $VMUUID
                else
                        logPrint "ERROR UUID $VMUUID Not Found" 1 0
                fi
        done < ${WANTED_UUIDS}
fi

BACKUP_LOCATION=${MOUNTPOINT}/${XSNAME}
BACKUP_DIRS=`ls $BACKUP_LOCATION`

for DIR in $BACKUP_DIRS ; do
        if [ $DIR -lt $BACKUP_DAYS ]; then
                REMOVE_DIR=$BACKUP_LOCATION/$DIR
                logPrint "check if directory exists $REMOVE_DIR" 0 0
                if [ -d $REMOVE_DIR ] && [ ! -z $DIR ] ; then
                        logPrint "remove $REMOVE_DIR"
                        rm -rf $REMOVE_DIR
                        REMOVE_STATUS=$?
                        logPrint "remove status $REMOVE_STATUS" 0 0
                        if [ $REMOVE_STATUS -ne 0 ]; then
                                logPrint "ERROR could not remove directory $REMOVE_DIR" 1 0
                        fi
                else
                        logPrint "ERROR directory $REMOVE_DIR does not exist. Someting went wrong"
                fi
        fi
done

umount ${MOUNTPOINT}
EXIT_STATUS_UMOUNT=$?
if [ $EXIT_STATUS_UMOUNT -ne 0 ]; then
        logPrint "ERROR in umount ${MOUNTPOINT}" 1 1
else
        logPrint "SUCCESS in umount ${MOUNTPOINT}" 0 0
        logPrint FINISH 0 0
        if grep -Fq "ERROR" ${nagiosLog} ; then
                logPrint "ERRORS are found. Could not remove $nagiosLog" 0 0
        else
                rm -f $nagiosLog
        fi
        rm -f $WANTED_UUIDS
        echo $DATE_TS > $LAST_RUN
fi
