if [ "$#" -ne 1 ] ; then
	echo "Please provide a number for the max backfills to run"
	exit 1
fi

ceph tell osd.*  injectargs  "--osd_max_backfills $1"
