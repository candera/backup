#!/bin/bash
# Write the file using LF for line endings
# -*- buffer-file-coding-system: unix -*- 

# Invoke via Windows Task Scheduler as: 
# \path\to\ShadowSpawn.exe C:\src\dir q: \cygwin\bin\bash.exe -l /path/to/backup.sh /cygdrive/q server path/to/dest

function print_usage 
{
  cat <<EOF 
Usage: `basename $0` src host dst

Backup SRC on localhost to DST on HOST, using rsync. The generated
directory structure looks like this:

HOST:DST
|-- current -> backup-201111206-085712
|-- backup-20111206-085712
|   |-- most recent copy of SRC
|-- previous-20111205-092117
|   |-- next most recent copy or SRC
|-- ...

etc.

previous copies are maintained using hardlinks, so minimal disk space
is consumed.
EOF
}

if [ -z "$3" ]; then
    print_usage
    exit 1
fi

SRC=$1/
HOST=$2
DST=$3

NOW=`date +%Y%m%d-%H%M%S`

CURRENT_BACKUP_DIR=${DST}/current
TIMESTAMPED_BACKUP_DIR=${DST}/backup-${NOW}

LOGFILE=/tmp/backup.${NOW}.log

# The trick here is that we're recursively making hardlinks to all the
# files, which takes almost no space. So when rsync does its copy,
# since it unlinks before updating, only changed files will be copied
# - anything that hasn't changed since the last backup will just be a
# hardlink.

# Process: copy to backup-YYYY-mm-dd-hh-MM-ss based on current, if it
# exists. If successful, link current to that dir.

echo "Creating hardlinks from ${TIMESTAMPED_BACKUP_DIR} to ${CURRENT_BACKUP_DIR}"
ssh ${HOST} "if [[ -d ${CURRENT_BACKUP_DIR} ]]; then cp -al \`readlink ${CURRENT_BACKUP_DIR}\` ${TIMESTAMPED_BACKUP_DIR}; fi"

SSH_RESULT=$?

if [ $SSH_RESULT -ne 0 ]; then
    email --from-name "Automated Backup" --from-addr "backup@wangdera.com" --smtp-server candera.sytes.net --smtp-port 2525 --subject "Backup Failed: `hostname`" candera@wangdera.com <<EOF
ssh cp -lr failed with error ${SSH_RESULT}.
EOF
    exit $SSH_RESULT
fi 

echo "Backing up from ${SRC} to ${HOST}:${CURRENT_BACKUP_DIR}"
rsync --archive --progress --delete --log-file=$LOGFILE $SRC ${HOST}:${TIMESTAMPED_BACKUP_DIR}

RSYNC_RESULT=$?

if [ $RSYNC_RESULT -ne 0 ]; then
    bzip2 -9 $LOGFILE
    email --from-name "Automated Backup" --from-addr "backup@wangdera.com" --smtp-server candera.sytes.net --smtp-port 2525 --attach ${LOGFILE}.bz2 --subject "Backup Failed: `hostname`" candera@wangdera.com <<EOF
rsync failed with error ${RSYNC_RESULT}. See attached file for details.
EOF
    exit $RSYNC_RESULT
else 
    email --from-name "Automated Backup" --from-addr "backup@wangdera.com" --smtp-server candera.sytes.net --smtp-port 2525 --subject "Backup Succeeded: `hostname`" candera@wangdera.com <<EOF
The backup succeeded.
EOF
    ssh ${HOST} "rm -f ${CURRENT_BACKUP_DIR} && ln -sf ${TIMESTAMPED_BACKUP_DIR} ${CURRENT_BACKUP_DIR}"

    # Remove all but the latest 30 backups
    ssh ${HOST} "find $DST -maxdepth 1 -type d -name 'backup-*' | sort -r | awk 'NR>3' | xargs rm -rf"

    # TODO: provide some sort of feedback (email?) on whether either
    # of the last two commands succeeded.
fi


