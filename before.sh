#!/bin/bash

export LC_ALL=en_GB.UTF-8 

VERSION="2.4"
STORAGEPATH="/kvm"
VIRSHPATH=`which virsh`
#VIRSHPATH="/usr/bin/virsh -d 4" 
#VIRSHPATH=echo
TIME=`date '+%d-%m-%Y_%H-%M'`
YESTERDAY=`date -d yesterday '+%d-%m-%Y'`
TODAY=`date '+%d-%m-%Y'`

echo `basename $0` version $VERSION

### Functions
remove_snapshot_file() {
# remove_snapshot_file <snapshot_file>
if [ -n "$1" ];
then
   if rm $1; then
      echo "Snapshot disk deleted"
   else
      echo "Can't remove disk file"
      exit 1
   fi
else
   echo "Need pass argument to function"
   exit 1
fi
}

check_for_blockjobs() {
# use this function without arguments
   if [ `$VIRSHPATH blockjob $VMNAME $DISK 2>/dev/null | grep -c "No current block job for $DISK"` -ne 1 ]
   then
      echo "ERROR: I've found active blockjobs for $VMNAME for disk $DISK, can't proceed. Check it manually"
      exit 1
   fi
}

if [ "$#" -lt 2 ]
then
    echo "Usage: $0 <vm name> <backup type> [<disk>] [<--no-quiesce>]"
    exit 1
else
   VMNAME=$1
   if [[ "$2" != "daily" && "$2" != "Incremental" && "$2" != "Differential" ]]
   then 
      BACKUPTYPE="Full"
   elif [[ "$2" != "Full" && "$2" != "monthly" ]]
   then
      BACKUPTYPE="Incremental"
   else
      echo "<backup type> must be daily (Incremental or Differential) or Full (monthly)"
      exit 1
   fi
fi

if [ "$3" == "" ]
then
   DISK="vda"
else
   DISK=$3
fi

if [ "$4" != "--no-quiesce" ]
then
   QUIESCE="--quiesce"
else
   QUIESCE=""
fi

# checking for Base snapshot
if ! $VIRSHPATH snapshot-list $VMNAME | grep "base"
then
   echo "Error: can't find the base snapshot. It's required for this backup system. You can create it mannually:"
   echo $VIRSHPATH snapshot-create-as $VMNAME base base
   exit 1
fi

# if backup type is daily
if [ $BACKUPTYPE = "Incremental" ]
then
   check_for_blockjobs
   # checking daily backup exist
   if [ `$VIRSHPATH snapshot-list $VMNAME | grep "daily" | wc -l` -ne 1 ]
   then
      echo "$VMNAME has no daily backup, then I'll create it..."
      if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name daily --description "Daily for $TIME" --disk-only --diskspec $DISK,snapshot=external,file=$STORAGEPATH/$VMNAME-daily.qcow2 --atomic $QUIESCE; then
         echo "Can't create snapshot. Error detected, exiting"
         exit 1
      fi
      echo "Current snapshot doesn't exist for $VMNAME, let's create it"
      if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "current on $TIME" --disk-only --diskspec $DISK,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $QUIESCE; then
         echo "Can't create snapshot. Error detected, exiting"
         exit 1
      fi
   else
      check_for_blockjobs
      echo "Daily backup found for $VMNAME"
      if [ `$VIRSHPATH snapshot-list $VMNAME | grep "current" | wc -l` -eq 1 ]
      then
         echo "Current snapshot exist for $VMNAME, let's merge it into daily and create new"
         if ! $VIRSHPATH blockcommit --domain $VMNAME $DISK --base $STORAGEPATH/$VMNAME-daily.qcow2 --active --verbose --pivot; then
             echo "Can't do blockcommit, error detected, exiting"
             exit 1
         fi
         if [ `$VIRSHPATH domblklist $VMNAME | grep $DISK | grep current | wc -l` -eq 0 ]
         then
            if [ -f $STORAGEPATH/$VMNAME-current.qcow2 ];
            then
               echo "removing old snapshot file"
               remove_snapshot_file $STORAGEPATH/$VMNAME-current.qcow2
               $VIRSHPATH snapshot-delete --domain $VMNAME current --metadata
            fi
            echo "Creating new current snapshot"
            if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "Current for $TIME" --disk-only --diskspec $DISK,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $QUIESCE; then
               echo "Can't create snapshot"
               exit 1
            fi
         fi
      else
         echo "Current snapshot doesn't exist for $VMNAME, let's create it"
         if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "Current on $TIME" --disk-only --diskspec $DISK,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $QUIESCE; then
            echo "Can't create snapshot. Exiting"
            exit 1
         fi
      fi
   fi # fi for checking daily backup exist
# or if backup monthly
elif [ $BACKUPTYPE = "Full" ]
then
   check_for_blockjobs
   echo "Full backup"
   if [ `$VIRSHPATH snapshot-list $VMNAME | grep "current" | wc -l` -eq 1 ]
   then
      echo "Current snapshot exist for $VMNAME, let's merge it into daily..."
      if ! $VIRSHPATH blockcommit --domain $VMNAME $DISK --base $STORAGEPATH/$VMNAME-daily.qcow2 --active --verbose --pivot; then
         echo "Can't do blockcommit for current snapshot. Exiting"
         exit 1
      fi
      if ! $VIRSHPATH snapshot-delete --domain $VMNAME "current" --metadata; then
         echo "Can't delete current snapshot. Exiting"
         exit 1
      fi
      remove_snapshot_file $STORAGEPATH/$VMNAME-current.qcow2
   fi # fi for current snapshot
   if [ `$VIRSHPATH snapshot-list $VMNAME | grep "daily" | wc -l` -eq 1 ]
   then
      echo "Daily snapshot exist for $VMNAME, let's merge it into base..."
      if ! $VIRSHPATH blockcommit --domain $VMNAME $DISK --base $STORAGEPATH/$VMNAME.qcow2 --active --verbose --pivot; then
         echo "Can't do blockcommit for current snapshot. Exiting"
         exit 1
      fi
      if ! $VIRSHPATH snapshot-delete --domain $VMNAME "daily" --metadata; then
         echo "Can't delete current snapshot. Exiting"
         exit 1
      fi
      remove_snapshot_file $STORAGEPATH/$VMNAME-daily.qcow2
   fi # fi for daily snapshot
   echo "Create new daily snapshot"
   if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name daily --description "daily on $TODAY" --disk-only --diskspec $DISK,snapshot=external,file=$STORAGEPATH/$VMNAME-daily.qcow2 --atomic $QUIESCE; then
      echo "Can't create new daily snapshot. Exiting"
      exit 1
   fi
   echo "Create new current snapshot"	
   if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "current for $TIME" --disk-only --diskspec $DISK,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $QUIESCE; then
      echo "Can't create new current snapshot. Exiting"
      exit 1
   fi
else # only for emergency case.because we have another check for correct backup type
   echo "I don't know what backup type you entered and how you enter here"
   exit 1
fi
