#!/bin/bash

#Lets exit if there is an error
set -e

#I got sick of pulling in new configs and updating this file for each tier of machine
#Now just put the variables down below in local.config and have fun.   
if [ -e ./local.config ] ; then source ./local.config ; else echo "No local config, exiting" ; exit 37 ; fi

#####################
#TODO 
# * Do some checks.  Did we find all the drives we expect?
# Journals per drive * journal drives discovered = discovered OSD devices * OSD per OSDdevice?
#
#
# * Make the ceph-create-volumes.sh output a variable instead of hard coded.
#####################

#####################
#Assumpition  
# even distribution of journals to OSD data drives. All drives of a specific type do a specific duty with no overlap 
#
#Journal drives x OSD per should = Number OSD
#####################

###  You shouldn't need to change stuff below this line  ###

if [ -z "$OSDModel" ] ; then
	echo "OSDModel not set, exiting"
	exit 12
fi

#If there aren't blacklisted drives, make up some serial that is blacklisted so everyone
#passes the check.
if [ -z "$OSDSerialBlacklist" ] ; then
        OSDSerialBlacklist="BIGNULLSTRINGTHATSHOULDNEVERBEASERIALNUMBER"
fi

if [ -z "$JournalSerialBlacklist" ] ; then
        JournalSerialBlacklist="BIGNULLSTRINGTHATSHOULDNEVERBEASERIALNUMBER"
fi

## Lets discover all the installed drives
#If we have a journal model defined, search for them and put in an array
if [ -n "$JournalModel" ] ; then
	JournalDevices="$(lsblk --nodeps --noheadings -p  -o name,serial,model | grep -P "${JournalModel}" | grep -Pv "$JournalSerialBlacklist" | awk '{ printf $1" " ; }')"
fi

#Find all OSD Devices and put in an array
OSDDevices=($(lsblk --nodeps --noheadings -p  -o name,serial,model | grep -P "${OSDModel}" | grep -Pv "$OSDSerialBlacklist" | awk '{ printf $1" " ; }'))

#If we have an old create volume script, just move it aside
if [ -e ceph-create-volumes.sh ] ; then mv ceph-create-volumes.sh ceph-create-volumes.sh.$(date +%s).backup ; fi

#Step through the OSD devices and make the approprate number of LVs.  Each LV is named after the serial number of the
#hosting device appended by the sequence number of how many data LVs per OSD.  
for OSD in ${OSDDevices[@]} ; do
	#Extract all the serial numbers into an array
	OSDSerial=$(lsblk --nodeps --noheadings -o serial ${OSD})
	OSDSerialList+=(${OSDSerial})

	#Create PV, VG and calculate size of the LV/LVs
	pvcreate ${OSD}
	vgcreate ${OSDSerial} ${OSD}
	OSDSize=$(expr $(pvdisplay ${OSD} -c | cut -d : -f 10) / ${DataperOSDDevice})

	#Loop to make the LVs
	for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
		lvcreate -l ${OSDSize} -n data.${DataperOSDDeviceCount} ${OSDSerial}
		#If we are reprovisioning OSDs you want to clean them or else they will replay history from the epoch in the superblock
		#Not too terrible if you have one or two joining.  A chunk of 36 joining at once will cause timeouts.
		dd if=/dev/zero bs=1M count=16 of=/dev/${OSDSerial}/data.${DataperOSDDeviceCount}
	done
done

#If we don't have any Journal model numbers defined, just skip this
if [ -n "$JournalModel" ] ; then
	#Internal pointer to what array element we are on
	OSDDevicesPointer=0

	#Step through the discovered journal devices to make LVs
	for Journal in ${JournalDevices[@]} ; do
		#Extract all the serial numbers into an array
		JournalSerial=$(lsblk --nodeps --noheadings -o serial ${Journal})
		JournalSerialList+=(${JournalSerial})

		#Create PV, VG and calculate size of the LV/LVs
		pvcreate ${Journal}
		vgcreate ${JournalSerial} ${Journal}
		JournalSize=$(expr $(pvdisplay ${Journal} -c | cut -d : -f 10) / ${OSDperJournal})

		#Loop to make the LVs
		for JournalperJournalDeviceCount in $(seq 1 ${OSDperJournal} ); do
			for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
				lvcreate -l ${JournalSize} -n journal.${OSDSerialList[${OSDDevicesPointer}]}.${DataperOSDDeviceCount} ${JournalSerial}
				#Everyone wants a nice clean journal
				dd if=/dev/zero bs=1M count=16 of=/dev/${JournalSerial}/journal.${OSDSerialList[${OSDDevicesPointer}]}.${DataperOSDDeviceCount}
			done
			let OSDDevicesPointer=OSDDevicesPointer+1
		done
	done
fi

#if we don't have a keyring for bootstrapping drives, grab it
if [ ! -e /var/lib/ceph/bootstrap-osd/ceph.keyring ] ; then ceph auth get client.bootstrap-osd  > /var/lib/ceph/bootstrap-osd/ceph.keyring ; fi

#Now we make the script to insert the OSDs into the cluster
#For loop stepping through all the OSDs discovered
for OSD in ${OSDSerialList[@]} ; do
	#Loop to step through multiple Data partitions per OSD
	for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
		#The most basic line to create an OSD.  We want an LVM to be created with data on an osd.  Don't newline it yet...
		echo -n "ceph-volume lvm prepare --data ${OSD}/data.${DataperOSDDeviceCount} " >> ceph-create-volumes.sh
		#Do we have journals?  
		if [ -n "$JournalModel" ] ; then 
			#We have journals!  Since everything is named after serial nubmers, just go find the LV with the correct name of OSDserial.sequence
			#Custom device class is if you are doing fancy things with ceph devices classes and need these to be somewhere specific. 
			#Newline enabled so we can keep on the loop.
			echo --block.db $(lvdisplay -c | grep journal.${OSD}.${DataperOSDDeviceCount} | cut -d : -f 1 | cut -d / -f 3-) ${CustomDeviceClass} >> ceph-create-volumes.sh
		else
			#No Journals.  Again we spit out the custom device class if defined and newline it.
			echo "${CustomDeviceClass}"  >> ceph-create-volumes.sh
		fi
	done
done
echo "ceph-volume lvm activate --all" >> ceph-create-volumes.sh
