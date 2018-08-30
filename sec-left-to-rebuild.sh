#!/bin/bash

tmp_file=$( mktemp --tmpdir=/dev/shm )
ceph status -f json > ${tmp_file}

#obj_left=$(ceph status | grep -Po '(?<=pgs:).*(?=objects misplaced)'| tr -d  ' ' | cut -d'/' -f1 )
#obj_rate=$(ceph status | sed -n 's/^\s\+recovery: [0-9]\+\.[0-9]* GiB\/s, \([0-9]\+\) objects\/s/\1/p')
obj_misplaced=$( jq .pgmap.misplaced_objects ${tmp_file} )
obj_degraded=$( jq .pgmap.degraded_objects ${tmp_file} )
obj_rate=$( jq .pgmap.recovering_objects_per_sec ${tmp_file} )

rm $tmp_file

obj_left=$(( obj_misplaced + obj_degraded ))

echo "Objects misplaced: ${obj_misplaced}"
echo "Objects degraded: ${obj_degraded}"
echo "Objects left: ${obj_left}"
echo "Recovery Rate: ${obj_rate} objects/sec"

time_left=$(( obj_left / obj_rate ))
echo "Time Left: ${time_left} sec"
sec=$(( time_left % 60 ))
time_left=$(( time_left / 60 ))
min=$(( time_left % 60 ))
time_left=$(( time_left / 60 ))
hour=$(( time_left % 24 ))
day=$(( time_left / 24 ))
printf "Time Left: %d-%02d:%02d:%02d\n" ${day} ${hour} ${min} ${sec}
