#!/bin/bash
# Version 2.1 

export LC_ALL=en_GB.UTF-8 

STORAGEPATH="/kvm"
VIRSHPATH=`which virsh`
#VIRSHPATH=echo
TIME=`date '+%d-%m-%Y_%H-%M'`
YESTERDAY=`date -d yesterday '+%d-%m-%Y'`
TODAY=`date '+%d-%m-%Y'`

### Functions
remove_snapshot_file() {
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

disk=${3-"vda"}
quiesce="--quiesce"

[ "$4" == "--no-quiesce" ] && quiesce=""

if [ "$3" != "vda" ]
then
  DISK=$3
else
  DISK="vda"
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
# checking daily backup exist
if [ `$VIRSHPATH snapshot-list $VMNAME | grep "daily" | wc -l` -ne 1 ]
then
	echo "$VMNAME has no daily backup, then I'll create it..."
	if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name daily --description "Daily for $TIME" --disk-only --diskspec $disk,snapshot=external,file=$STORAGEPATH/$VMNAME-daily.qcow2 --atomic $quiesce; then
		echo "Can't create snapshot. Error detected, exiting"
		exit 1
	fi
	echo "Current snapshot doesn't exist for $VMNAME, let's create it"
	if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "current on $TIME" --disk-only --diskspec $disk,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $quiesce; then
		echo "Can't create snapshot. Error detected, exiting"
		exit 1
	fi
else
	echo "Daily backup found for $VMNAME"
	if [ `$VIRSHPATH snapshot-list $VMNAME | grep "current" | wc -l` -eq 1 ]
	then
		echo "Current snapshot exist for $VMNAME, let's merge it into daily and create new"
		if ! $VIRSHPATH blockcommit --domain $VMNAME $disk --base $STORAGEPATH/$VMNAME-daily.qcow2 --active --verbose --pivot; then
			echo "Can't do blockcommit, error detected, exiting"
			exit 1
		fi
		if [ `$VIRSHPATH domblklist $VMNAME | grep $disk | grep current | wc -l` -eq 0 ]
		then
			if [ -f $STORAGEPATH/$VMNAME-current.qcow2 ];
			then
				echo "removing old snapshot file"
				remove_snapshot_file $STORAGEPATH/$VMNAME-current.qcow2
				$VIRSHPATH snapshot-delete --domain $VMNAME current --metadata
			fi
			echo "Creating new current snapshot"
			if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "Current for $TIME" --disk-only --diskspec $disk,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $quiesce; then
				echo "Can't create snapshot"
				exit 1
			fi
		fi
	else
		echo "Current snapshot doesn't exist for $VMNAME, let's create it"
	        if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "Current on $TIME" --disk-only --diskspec $disk,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $quiesce; then
			echo "Can't create snapshot. Exiting"
			exit 1
		fi
	fi
fi # fi for checking daily backup exist
elif [ $BACKUPTYPE = "Full" ]
then
	echo "Full backup"
	if [ `$VIRSHPATH snapshot-list $VMNAME | grep "current" | wc -l` -eq 1 ]
        then
		echo "Current snapshot exist for $VMNAME, let's merge it into daily..."
		if ! $VIRSHPATH blockcommit --domain $VMNAME $disk --base $STORAGEPATH/$VMNAME-daily.qcow2 --active --verbose --pivot; then
			echo "Can't do blockcommit for current snapshot. Exiting"
			exit 1
		fi
		if ! $VIRSHPATH snapshot-delete --domain $VMNAME "current" --metadata; then
			echo "Can't delete current snapshot. Exiting"
			exit 1
		fi
		remove_snapshot_file $STORAGEPATH/$VMNAME-current.qcow2
	fi
	if [ `$VIRSHPATH snapshot-list $VMNAME | grep "daily" | wc -l` -eq 1 ]
        then
		echo "Daily snapshot exist for $VMNAME, let's merge it into base..."
		if ! $VIRSHPATH blockcommit --domain $VMNAME $disk --base $STORAGEPATH/$VMNAME.qcow2 --active --verbose --pivot; then
			echo "Can't do blockcommit for current snapshot. Exiting"
			exit 1
		fi
		if ! $VIRSHPATH snapshot-delete --domain $VMNAME "daily" --metadata; then
			echo "Can't delete current snapshot. Exiting"
			exit 1
		fi
		remove_snapshot_file $STORAGEPATH/$VMNAME-daily.qcow2
	fi
	echo "Create new daily snapshot"
        if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name daily --description "daily on $TODAY" --disk-only --diskspec $disk,snapshot=external,file=$STORAGEPATH/$VMNAME-daily.qcow2 --atomic $quiesce; then
		echo "Can't create new daily snapshot. Exiting"
		exit 1
	fi
	echo "Create new current snapshot"	
	if ! $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "current for $TIME" --disk-only --diskspec $disk,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic $quiesce; then
		echo "Can't create new current snapshot. Exiting"
		exit 1
	fi
else # only for emergency case.because we have another check for correct backup type
	echo "I don't know what backup type you entered and how you enter here"
	exit 1
fi
