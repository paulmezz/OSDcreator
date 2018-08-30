#!/bin/bash

#Lets exit if there is an error
set -e

#TODO
# Do some checks.  Did we find all the drives we expect?
# Journals per drive * journal drives discovered = discovered OSD devices * OSD per OSDdevice?

#TODO
# Break this into functions so it can be called easier with internal journals OR build  around it

#TODO
# Make the ceph-creatae-volumes.sh output a variable instead of hard coded.


#Journal drives x OSD per should = Number OSD
JournalModel="MTFDHAX1T2MCF-1AN1ZABYY"
JournalDevices="$(lsblk --nodeps --noheadings -p  -o name,serial,model | grep -P $JournalModel | awk '{ printf $1" " ; }')"

OSDModel="ST10000NM0206|ST10000NM0226"
OSDDevices=($(lsblk --nodeps --noheadings -p  -o name,serial,model | grep -P $OSDModel | awk '{ printf $1" " ; }'))

OSDperJournal=18
DataperOSDDevice=1
NumberOfOSDs=36

#TODO These should be calculated instead of static
OSDSize=2384383
JournalSize=15897


###  You shouldn't need to change stuff below this line  ###

#Initialize a counter.  Don't touch this unless you _REALLY_ know what you are doing. 
OSDDevicesPointer=0
if [ -e ceph-create-volumes.sh ] ; then mv ceph-create-volumes.sh ceph-create-volumes.sh.$(date +%s).backup ; fi

#Step through discovered journals
for JD in ${JournalDevices[@]}; do
	#Pull serial number and create PV/VG
	JDSerial=$(lsblk --nodeps --noheadings -o serial ${JD})
	pvcreate ${JD}
	vgcreate ${JDSerial} ${JD}

	#Create Journals per device
	for JI in $(seq 1 $OSDperJournal); do
		#Makes sense to put the OSD create here as we already are stepping through
		#the journals.  We can also be smarter with naming.
		OSDSerial=$(lsblk --nodeps --noheadings -o serial ${OSDDevices[$OSDDevicesPointer]})

		for DataperOSDDeviceCount in $(seq 1 $DataperOSDDevice); do
			#Make Journal LV
			lvcreate -l ${JournalSize} -n journal.${OSDSerial}.${DataperOSDDeviceCount} ${JDSerial}
			dd if=/dev/zero bs=1M count=1 of=/dev/${JDSerial}/journal.${OSDSerial}.${DataperOSDDeviceCount}

			#Make OSD PV/VG/LV
			pvcreate ${OSDDevices[$OSDDevicesPointer]}
			vgcreate ${OSDSerial} ${OSDDevices[$OSDDevicesPointer]}
			lvcreate -l ${OSDSize} -n data.${DataperOSDDeviceCount} ${OSDSerial}
			dd if=/dev/zero bs=1M count=1 of=/dev/${OSDSerial}/data.${DataperOSDDeviceCount}

			#Make the acual ceph volume
			echo ceph-volume lvm create --data ${OSDSerial}/data.1 --block.db ${JDSerial}/journal.${OSDSerial}.${DataperOSDDeviceCount} >> ceph-create-volumes.sh
		done

		#Pick the next drive	
		let OSDDevicesPointer=OSDDevicesPointer+1
	done
done


exit 0


