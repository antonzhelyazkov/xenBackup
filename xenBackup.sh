#!/bin/bash
#
# Written By: Anton Antonov
# Created date: Jul 25 2017
# Version: 1.0.1
#

VERBOSE=0
DATE=`date +%Y%m%d%H%M%S`
DATE_TS=`date +%s`
XSNAME=`echo $HOSTNAME`
UUIDFILE=/tmp/xen-uuids.txt
WANTED_UUIDS=/tmp/xen-uuids-wanted.txt
NFS_SERVER_IP="192.168.0.1"
MOUNTPOINT=/mnt/backup
FILE_LOCATION_ON_NFS="/mnt/store/nfs"
SCRIPT_LOG=/var/log/xenBackup.log
NAGIOS_LOG=/var/log/xenBackupNagios.inf
LAST_RUN=/var/log/xenBackup.last

KEEP_BACKUP_DAYS=4
BACKUP_DAYS=`date +%Y%m%d%H%M%S -d "$KEEP_BACKUP_DAYS day ago"`

### Functions ###

function logPrint() {
MESSAGE=$1
echo `date` $MESSAGE >> $SCRIPT_LOG

if [ $VERBOSE -eq 1 ]; then
        echo $MESSAGE
fi
}

function backup() {
UUID=$1
VMNAME=`xe vm-list uuid=$UUID | grep name-label | cut -d":" -f2 | sed 's/^ *//g'`
SNAPUUID=`xe vm-snapshot uuid=$UUID new-name-label="SNAPSHOT-$UUID-$DATE"`

xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPUUID}
TEMPLATE_STATUS=$?
if [ $TEMPLATE_STATUS -ne 0 ]; then
        ERR_MSG="ERROR Template Problem"
        logPrint $ERR_MSG
        echo $ERR_MSG >> $NAGIOS_LOG
fi

xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME.xva"
EXPORT_STATUS=$?
if [ $EXPORT_STATUS -ne 0 ]; then
        ERR_MSG="ERROR Export Snapshot Problem"
        logPrint $ERR_MSG
        echo $ERR_MSG >> $NAGIOS_LOG
fi

xe vm-uninstall uuid=${SNAPUUID} force=true
REMOVE_STATUS=$?
if [ $REMOVE_STATUS -ne 0 ]; then
        ERR_MSG="ERROR Remove Snapshot Problem"
        logPrint $ERR_MSG
        echo $ERR_MSG >> $NAGIOS_LOG
fi
}

### Create mount point

logPrint START

if [ -f $NAGIOS_LOG ]; then
        logPrint "file $NAGIOS_LOG exists EXIT!"
        exit
else
        echo $$ > $NAGIOS_LOG
fi

if [ -d $WANTED_UUIDS ]; then
        ERR_MSG="ERROR file $WANTED_UUIDS exists. Something went wrong. EXIT"
        logPrint $ERR_MSG
        echo $ERR_MSG >> $NAGIOS_LOG
        exit
fi

for UUID in "$@"
do
        echo $UUID >> $WANTED_UUIDS
done

if [ -d $MOUNTPOINT ]; then
        logPrint "Directory $MOUNTPOINT exists"
        mount ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}
        EXIT_STATUS_MOUNT=$?
        if [ $EXIT_STATUS_MOUNT -ne 0 ]; then
                logPrint "ERROR in mount ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}"
                exit 0
        else
                logPrint "SUCCESS in mount ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}"
        fi
else
        logPrint "Directory $MOUNTPOINT does NOT exist"; exit 0
fi

BACKUPPATH=${MOUNTPOINT}/${XSNAME}/${DATE}

if [ -w $MOUNTPOINT ]; then
        logPrint "Directory $MOUNTPOINT is writtable"
else
        logPrint "Directory $MOUNTPOINT is NOT writtable"
        exit 0
fi

mkdir -p ${BACKUPPATH}
if [ ! -d ${BACKUPPATH} ]; then
        logPrint "Directory $BACKUPPATH is does NOT exist"
        exit 0
fi

# Fetching list UUIDs of all VMs running on XenServer
xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | cut -d":" -f2 > ${UUIDFILE}

COUNT_UUIDFILE=$(wc -l < "${UUIDFILE}")

if [ -f $WANTED_UUIDS ]; then
        COUNT_UUIDFILE_WANTED=$(wc -l < "${WANTED_UUIDS}")
fi

if [ -z $COUNT_UUIDFILE ]; then
        ERR_MSG="ERROR No VMs found"
        logPrint $ERR_MSG
        echo $ERR_MSG >> $NAGIOS_LOG
        exit
fi

if [ -z $COUNT_UUIDFILE_WANTED ]; then
        logPrint "backup all VMs"
        while read VMUUID
        do
                logPrint "Working on $VMUUID"
                backup $VMUUID
        done < ${UUIDFILE}
else
        while read VMUUID
        do
                if grep -Fq "$VMUUID" ${UUIDFILE} ; then
                        logPrint "Working on $VMUUID"
                        backup $VMUUID
                else
                        ERR_MSG="ERROR UUID $VMUUID Not Found"
                        logPrint $ERR_MSG
                        echo $ERR_MSG
                        echo $ERR_MSG >> $NAGIOS_LOG
                fi
        done < ${WANTED_UUIDS}
fi

BACKUP_LOCATION=${MOUNTPOINT}/${XSNAME}
BACKUP_DIRS=`ls $BACKUP_LOCATION`

for DIR in $BACKUP_DIRS ; do
        if [ $DIR -lt $BACKUP_DAYS ]; then
                REMOVE_DIR=$BACKUP_LOCATION/$DIR
                logPrint "check if directory exists $REMOVE_DIR"
                if [ -d $REMOVE_DIR ] && [ ! -z $DIR ] ; then
                        logPrint "remove $REMOVE_DIR"
                        rm -rf $REMOVE_DIR
                        REMOVE_STATUS=$?
                        logPrint "remove status $REMOVE_STATUS"
                        if [ $REMOVE_STATUS -ne 0 ]; then
                                ERR_MSG="ERROR could not remove directory $REMOVE_DIR"
                                logPrint $ERR_MSG
                                echo $ERR_MSG >> $NAGIOS_LOG
                        fi
                else
                        ERR_MSG="ERROR directory $REMOVE_DIR does not exist. Someting went wrong"
                        logPrint $ERR_MSG
                        echo $ERR_MSG >> $NAGIOS_LOG
                fi
        fi
done

umount ${MOUNTPOINT}
EXIT_STATUS_UMOUNT=$?
if [ $EXIT_STATUS_UMOUNT -ne 0 ]; then
        ERR_MSG="ERROR in umount ${MOUNTPOINT}"
        logPrint $ERR_MSG
        echo $ERR_MSG >> $NAGIOS_LOG
        exit 0
else
        logPrint "SUCCESS in umount ${MOUNTPOINT}"
        logPrint FINISH
        if grep -Fq "ERROR" ${NAGIOS_LOG} ; then
                logPrint "ERRORS are found. Could not remove $NAGIOS_LOG"
        else
                rm -f $NAGIOS_LOG
        fi
        rm -f $WANTED_UUIDS
        echo $DATE_TS > $LAST_RUN
fi
