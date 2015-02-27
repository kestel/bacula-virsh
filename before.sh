#!/bin/bash

STORAGEPATH="/kvm"
VIRSHPATH=`which virsh`
TIME=`date '+%d-%m-%Y_%H-%M'`
YESTERDAY=`date -d yesterday '+%d-%m-%Y'`
TODAY=`date '+%d-%m-%Y'`

if [ "$#" -ne 2 ]
then
	echo "Usage: $0 <vm name> <backup type>"
	exit 1
else
	VMNAME=$1
	if [[ "$2" != "daily" && "$2" != "Incremental" && "$2" != "Differential" ]]
	then 
		BACKUPTYPE="Incremental"
	elif [[ "$2" != "Full" && "$2" != "monthly" ]]
	then
		BACKUPTYPE="Full"
	else
		echo "<backup type> must be daily (Incremental or Differential) or Full (monthly)"
		exit 1
	fi
fi

# checking for Base snapshot
if [ `$VIRSHPATH snapshot-list $VMNAME | grep "base" | wc -l` -ne 1 ]
then
	echo "I can't find the base snapshot. It's required for this backup system."
	while true; do
		read -p "Should I create it? [y/N]" yn
		case $yn in
			[Yy]* ) echo "Okay, I'll create it..."; $VIRSHPATH snapshot-create-as $VMNAME base base; break;;
			[Nn]* ) echo "Okay, exiting"; exit;;
			* ) echo "Please answer yes or no.";;
		esac
	done
fi

# if backup type is daily
if [ $BACKUPTYPE = "Incremental" ]
then
# checking daily backup exist
if [ `$VIRSHPATH snapshot-list $VMNAME | grep "daily" | wc -l` -ne 1 ]
then
	echo "$VMNAME has no daily backup, then I'll create it..."
	$VIRSHPATH snapshot-create-as --domain $VMNAME --name daily --description "Daily for $TIME" --disk-only --diskspec vda,snapshot=external,file=$STORAGEPATH/$VMNAME-daily.qcow2 --atomic --quiesce
	echo "Current snapshot doesn't exist for $VMNAME, let's create it"
	$VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "current on $TIME" --disk-only --diskspec vda,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic --quiesce
else
	echo "Daily backup found for $VMNAME"
	if [ `$VIRSHPATH snapshot-list $VMNAME | grep "current" | wc -l` -eq 1 ]
	then
		echo "Current snapshot exist for $VMNAME, let's merge it into daily and create new"
		$VIRSHPATH blockcommit --domain $VMNAME vda --base $STORAGEPATH/$VMNAME-daily.qcow2 --active --verbose --pivot
		if [ `$VIRSHPATH domblklist $VMNAME | grep vda | grep current | wc -l` -eq 0 ]
		then
			if [ -f $STORAGEPATH/$VMNAME-current.qcow2 ];
			then
				echo "removing old snapshot file"
				rm -f $STORAGEPATH/$VMNAME-current.qcow2
				$VIRSHPATH snapshot-delete --domain $VMNAME current --metadata
			fi
			echo "Creating new current snapshot"
		        $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "Current for $TIME" --disk-only --diskspec vda,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic --quiesce
		fi
	else
		echo "Current snapshot doesn't exist for $VMNAME, let's create it"
	        $VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "Current on $TIME" --disk-only --diskspec vda,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic --quiesce
	fi
fi # fi for checking daily backup exist
elif [ $BACKUPTYPE = "Full" ]
then
	echo "Full backup"
	if [ `$VIRSHPATH snapshot-list $VMNAME | grep "current" | wc -l` -eq 1 ]
        then
		echo "Current snapshot exist for $VMNAME, let's merge it into daily..."
		$VIRSHPATH blockcommit --domain $VMNAME vda --base $STORAGEPATH/$VMNAME-daily.qcow2 --active --verbose --pivot
		$VIRSHPATH snapshot-delete --domain $VMNAME "current" --metadata
		rm -f $STORAGEPATH/$VMNAME-current.qcow2
	fi
	if [ `$VIRSHPATH snapshot-list $VMNAME | grep "daily" | wc -l` -eq 1 ]
        then
		echo "Daily snapshot exist for $VMNAME, let's merge it into base..."
		$VIRSHPATH blockcommit --domain $VMNAME vda --base $STORAGEPATH/$VMNAME.qcow2 --active --verbose --pivot
		$VIRSHPATH snapshot-delete --domain $VMNAME "daily" --metadata
                rm -f $STORAGEPATH/$VMNAME-daily.qcow2
	fi
	echo "Create new daily snapshot"
        $VIRSHPATH snapshot-create-as --domain $VMNAME --name daily --description "daily on $TODAY" --disk-only --diskspec vda,snapshot=external,file=$STORAGEPATH/$VMNAME-daily.qcow2 --atomic --quiesce
	echo "Create new current snapshot"	
	$VIRSHPATH snapshot-create-as --domain $VMNAME --name current --description "current for $TIME" --disk-only --diskspec vda,snapshot=external,file=$STORAGEPATH/$VMNAME-current.qcow2 --atomic --quiesce
else # only for emergency case.because we have another check for correct backup type
	echo "I don't know what backup type you entered and how you enter here"
	exit 1
fi
