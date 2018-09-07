#!/bin/bash

#Lets exit if there is an error
set -e

#TODO
# Do some checks.  Did we find all the drives we expect?
# Journals per drive * journal drives discovered = discovered OSD devices * OSD per OSDdevice?

#TODO
# Make the ceph-creatae-volumes.sh output a variable instead of hard coded.

#Assumpition  
# even distribution of journals to OSD data drives.  

#Journal drives x OSD per should = Number OSD
#JournalModel="MTFDHAX1T2MCF-1AN1ZABYY"
JournalModel=""
if [ -n "$JournalModel" ] ; then
	JournalDevices="$(lsblk --nodeps --noheadings -p  -o name,serial,model | grep -P $JournalModel | awk '{ printf $1" " ; }')"
fi

#OSDModel="ST10000NM0206|ST10000NM0226"
OSDModel="PHKS817201ZC750BGN"
OSDDevices=($(lsblk --nodeps --noheadings -p  -o name,serial,model | grep -P $OSDModel | awk '{ printf $1" " ; }'))

#If you are using internal journals, make the JournalModel above ""  
OSDperJournal=18
DataperOSDDevice=1
NumberOfOSDs=36

#TODO These should be calculated instead of static
#OSDSize=2384383
#JournalSize=15897


###  You shouldn't need to change stuff below this line  ###

if [ -e ceph-create-volumes.sh ] ; then mv ceph-create-volumes.sh ceph-create-volumes.sh.$(date +%s).backup ; fi


for OSD in ${OSDDevices[@]} ; do
	OSDSerial=$(lsblk --nodeps --noheadings -o serial ${OSD})
	OSDSerialList+=(${OSDSerial})

	#One PV/VG per device
	pvcreate ${OSD}
	vgcreate ${OSDSerial} ${OSD}
	OSDSize=$(expr $(pvdisplay ${OSD} -c | cut -d : -f 10) / ${DataperOSDDevice})

	#One or more LV per device
	for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
		lvcreate -l ${OSDSize} -n data.${DataperOSDDeviceCount} ${OSDSerial}
		#If we are reprovisioning OSDs you want to clean them or else they will replay history from the epoch in the superblock
		dd if=/dev/zero bs=1M count=1 of=/dev/${OSDSerial}/data.${DataperOSDDeviceCount}
	done
done

#If we don't have any Journal model numbers defined, just skip this
if [ -n "$JournalModel" ] ; then
	OSDDevicesPointer=0
	for Journal in ${JournalDevices[@]} ; do
		JournalSerial=$(lsblk --nodeps --noheadings -o serial ${Journal})
		JournalSerialList+=(${JournalSerial})

		#One PV/VG per device
		pvcreate ${Journal}
		vgcreate ${JournalSerial} ${Journal}
		JournalSize=$(expr $(pvdisplay ${Journal} -c | cut -d : -f 10) / ${OSDperJournal})

		#One or more LV per device
		for JournalperJournalDeviceCount in $(seq 1 $OSDperJournal); do
			for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
				lvcreate -l ${JournalSize} -n journal.${OSDSerialList[${OSDDevicesPointer}]}.${DataperOSDDeviceCount} ${JournalSerial}
			done	
			let OSDDevicesPointer=OSDDevicesPointer+1
		done
	done
fi

for OSD in ${OSDSerialList[@]} ; do
	for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
		echo -n "ceph-volume lvm create --data ${OSD}/data.${DataperOSDDeviceCount} " >> ceph-create-volumes.sh
		if [ -n "$JournalModel" ] ; then 
			echo --block.db $(lvdisplay -c | grep journal.${OSDSerial}.${DataperOSDDeviceCount} | cut -d : -f 1 | cut -d / -f 3-) >> ceph-create-volumes.sh
		else
			echo "" >> ceph-create-volumes.sh
		fi
	done
done

##Step through discovered journals
#for JD in ${JournalDevices[@]} ; do
#	#Pull serial number and create PV/VG
#	JDSerial=$(lsblk --nodeps --noheadings -o serial ${JD})
#	pvcreate ${JD}
#	vgcreate ${JDSerial} ${JD}

#	#Create Journals per device
#	for JI in $(seq 1 $OSDperJournal); do
#		#Makes sense to put the OSD create here as we already are stepping through
#		#the journals.  We can also be smarter with naming.
#		OSDSerial=$(lsblk --nodeps --noheadings -o serial ${OSDDevices[$OSDDevicesPointer]})

#		for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
#			#Make Journal LV
#			lvcreate -l ${JournalSize} -n journal.${OSDSerial}.${DataperOSDDeviceCount} ${JDSerial}
#			dd if=/dev/zero bs=1M count=1 of=/dev/${JDSerial}/journal.${OSDSerial}.${DataperOSDDeviceCount}
#			#ceph-volume lvm zap /dev/${JDSerial}/journal.${OSDSerial}.${DataperOSDDeviceCount}

#			#Make OSD PV/VG/LV
#			pvcreate ${OSDDevices[$OSDDevicesPointer]}
#			vgcreate ${OSDSerial} ${OSDDevices[$OSDDevicesPointer]}
#			lvcreate -l ${OSDSize} -n data.${DataperOSDDeviceCount} ${OSDSerial}
#			dd if=/dev/zero bs=1M count=1 of=/dev/${OSDSerial}/data.${DataperOSDDeviceCount}
#			#ceph-volume lvm zap /dev/${OSDSerial}/data.${DataperOSDDeviceCount}

#			#Make the acual ceph volume
#			echo ceph-volume lvm create --data ${OSDSerial}/data.${DataperOSDDeviceCount} --block.db ${JDSerial}/journal.${OSDSerial}.${DataperOSDDeviceCount} >> ceph-create-volumes.sh
#		done

#		#Pick the next drive	
#		let OSDDevicesPointer=OSDDevicesPointer+1
#	done
#done


exit 0


