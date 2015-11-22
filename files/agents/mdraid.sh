#!/bin/bash

#
# mdraid (normal) assemble/run/stop/etc. agent
#
#
# Copyright (C) 2013 Jakov Sosic. All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

. $(dirname $0)/ocf-shellfuncs
. $(dirname $0)/utils/member_util.sh

rv=0

# set variables to defaults
MDADM_CONF="/etc/mdadm.conf"
MD_UUID=""
MD_NAME=""

# verifies all settings and files
mdraid_verify_all() {
        # if file doesn't exist, exit immediately
        [ ! -f "$OCF_RESKEY_config_file" ] && return $OCF_ERR_ARGS

        # read data into array
        md_array=( $( cat $OCF_RESKEY_config_file ) )

        # if first element is not ARRAY, exit with error
        if [ "${md_array[0]}" != "ARRAY" ]; then
		ocf_log err "mdraid: Improper setup detected"
		ocf_log err "* file \"${OCF_RESKEY_config_file}\" doesn't contain ARRAY"
		return $OCF_ERR_GENERIC
	fi

	# try to find $OCF_RESKEY_name in config file
	NAMEFOUND=0

        # try to find out UUID of md device
        for i in `seq 0 $((${#md_array[@]} - 1))`; do
                if [[ "${md_array[$i]}" = *UUID* ]]; then
                        MD_UUID=`echo ${md_array[$i]} | cut -d= -f 2`
                elif [[ "${md_array[$i]}" = *name=* ]]; then
			MD_NAME=`echo ${md_array[$i]} | cut -d= -f 2 | cut -d: -f 1`
			[ "xx${OCF_RESKEY_name}" == "xx${MD_NAME}" ] && NAMEFOUND=1
		fi
        done

	# if name is not found in configuration file, fail
	if [ $NAMEFOUND -eq 0 ]; then
		ocf_log err "mdraid: Improper setup detected"
		ocf_log err "* device \"${OCF_RESKEY_name}\" not found in config file \"${OCF_RESKEY_config_file}\""
 		return $OCF_ERR_GENERIC
	fi

	# if uuid is not parsed we cannot continue
        if [ -z $MD_UUID ]; then
		ocf_log err "mdraid: Improper setup detected"
		ocf_log err "* UUID of device \"${OCF_RESKEY_name}\" not found in config file \"${OCF_RESKEY_config_file}\""
		return $OCF_ERR_GENERIC
	fi

	# check if md device with assigned uuid exists on this system
	if [ -z "$(/sbin/mdadm -Es | /bin/grep $MD_UUID)" ]; then
		ocf_log err "mdraid: Improper setup detected"
		ocf_log err "* device \"${OCF_RESKEY_name}\" not found on local system"
		return $OCF_ERR_ARGS
	fi

	# check if resource is ignored in mdadm.conf
	/bin/egrep -i "^ARRAY.*<IGNORE>.*${MD_UUID}" $MDADM_CONF > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		ocf_log err "mdraid: Improper setup detected"
		ocf_log err "* device \"${OCF_RESKEY_name}\" not ignored in ${MDADM_CONF}"
		return $OCF_ERR_GENERIC
	fi

	# check if initrd is newer than mdadm.conf - we don't wanna nodes
	# to automaticly activate ignored md device on boot
	if [ "$(find /boot -name *.img -newer $MDADM_CONF)" == "" ]; then
		ocf_log warn "mdraid: Manual intervention required."
		ocf_log warn "* initrd image needs to be newer than ${MDADM_CONF}"
	fi

	# so far so good
        return $OCF_SUCCESS
}

# list active nodes, depending on $1: all, remote or local
list_active_nodes(){
	ACTIVE=""

	# get list of remote nodes
	localnode=$(local_node_name)
	list="`/usr/sbin/ccs_tool lsnode | /bin/grep -v $localnode | /bin/sed '/^$/,/Fencetype/d' | /bin/awk '{ printf("%s ", $1); } END { printf( "\n" ); }'`"

	# check if all hosts in list are cluster members
	# and add them to variable ACTIVE
	for HOST in $list; do
		# check if node is alive
		is_node_member_clustat $HOST
		if [ $? -ne 0 ]; then
			break
		fi
		ACTIVE="$HOST $ACTIVE"
	done
}

# checks wether array is assembled on local node, returns 0 if active
check_md_status(){
	/usr/bin/test -h "/dev/disk/by-id/md-uuid-$MD_UUID"
	[ $? -eq 0 ] && return $OCF_SUCCESS || return $OCF_ERR_GENERIC
}

# checks health of an array
check_md_health(){
	# check if array is in FAILED state
	STATE="`/sbin/mdadm --misc --detail /dev/disk/by-id/md-uuid-$MD_UUID | /bin/grep 'State :'`"
	if [[ "${STATE}" =~ FAILED ]]; then
		ocf_log err "mdraid: array failed"
		ocf_log err "* device \"${OCF_RESKEY_name}\" is in FAILED state"
		return $OCF_ERR_GENERIC
	fi

	# so far so good
	return $OCF_SUCCESS
}

# stops inactive array if we started it
rollback_md(){
	TMPIFS=$IFS
	IFS=$'\n'
	for i in `/bin/grep inactive /proc/mdstat`; do
		# return IFS to it's original value
		IFS=$TMPIFS
		
		# read data into array
		mdstat_array=( $( /bin/echo $i ) )
		
		# itterate trough disks
		for j in `seq 3 $((${#mdstat_array[@]} - 1))`; do
			# parse the device name
			device=`/bin/echo ${mdstat_array[$j]} | /bin/sed 's|\(.*\)\[.*|/dev/\1|'`
			
			# get the array uuid
			cur_uuid=`/sbin/mdadm --examine $device | /bin/grep 'Array UUID :' | /bin/sed 's|.*: ||'`
			
			# stop the array and report back
			if [ "xx${cur_uuid}" == "xx${MD_UUID}" ]; then
				ocf_log dbg "mdraid: trying to stop inactive array \"$OCF_RESKEY_name\""
				/sbin/mdadm --stop "/dev/${mdstat_array[0]}"
				if [ $? -eq 0 ]; then
					ocf_log dbg "* array \"$OCF_RESKEY_name\" stopped succesfully"
				else
					ocf_log dbg "* failed to stop array \"$OCF_RESKEY_name\", exit code: $?"
				fi
				ocf_log warn "mdraid: Manual intervention required."
				ocf_log warn "* Array \"$OCF_RESKEY_name\" assembles as inactive!"
				break
			fi
		done
	done

	return $OCF_SUCCESS
}


# checks status of md on remote nodes, returns 0 if inactive
check_md_remote_status(){
	# if remote checks are disabled return success
	[ ${OCF_RESKEY_ssh_check} -ne 1 ] && return $OCF_SUCCESS

	# get list of nodes
	list_active_nodes

	# if there is no node, something is badly broken
	if [ "xx${ACTIVE}" = "xx" ]; then
		ocf_log notice "${SERVICENAME} - ${RESOURCE}: no active nodes"
		return $OCF_ERR_GENERIC
	fi

	# loop through list of nodes
	for node in $ACTIVE; do
		# only check remote hosts
		if [ "xx$node" != "xx$(local_node_name)" ]; then
			/usr/bin/ssh $node "/usr/bin/test -h \"/dev/disk/by-id/md-uuid-${MD_UUID}\""
			if [ $? -eq 0 ]; then
				ocf_log err "mdraid: Improper setup detected"
				ocf_log err "* device \"${OCF_RESKEY_name}\" is active on node \"$node\""
				return $OCF_ERR_GENERIC
			fi
		fi
	done

	# md is not active anywhere
	return $OCF_SUCCESS
}

# stops md device
stop_md(){
	# let's stop md
	/sbin/mdadm --stop /dev/disk/by-id/md-uuid-${MD_UUID}
	if [ $? -ne 0 ]; then
		ocf_log err "mdraid: Action failed"
		ocf_log err "* device \"${OCF_RESKEY_name}\" failed to stop correctly"
		return $OCF_ERR_GENERIC
	fi
	return $?
}

# assembles md device
assemble_md(){
	# so far so good, so let's activate md
	/sbin/mdadm --assemble --scan -c ${OCF_RESKEY_config_file} --uuid "${MD_UUID}"
	if [ $? -ne 0 ]; then
		ocf_log err "mdraid: Assemble failed"
		ocf_log err "* device \"${OCF_RESKEY_name}\" didn't assemble properly."
		rollback_md
		return $OCF_ERR_GENERIC
	fi

	# if the health is OK, succeed, else, rollback action
	check_md_health && return $OCF_SUCCESS || rollback_md
}

#
# main
#

# This one doesn't need to pass the verify check
case $1 in
  meta-data)
	cat `echo $0 | sed 's/^\(.*\)\.sh$/\1.metadata/'` && exit $OCF_SUCCESS
        ;;
esac

# verify setup
mdraid_verify_all      || exit $?
check_md_remote_status || exit $?

# main action
case $1 in
  start)
	# succeed if the device is *active* locally
	check_md_status && exit $OCF_SUCCESS

	# start the device
        assemble_md
	if [ $? -ne 0 ]; then
		ocf_log err "mdraid: Action failed"
		ocf_log err "* device \"${OCF_RESKEY_name}\" failed to assemble correctly"
                exit $OCF_ERR_GENERIC
	else
		ocf_log info SUCCESS
		exit $OCF_SUCCESS
	fi
	;;
  stop)
	# suceed if the device is *not active* locally
	check_md_status || exit $OCF_SUCCESS

	# stop the device
	stop_md
	if [ $? -ne 0 ]; then
		ocf_log err "mdraid: Action failed"
		ocf_log err "* device \"${OCF_RESKEY_name}\" failed to stop correctly"
		exit $OCF_ERR_GENERIC
	else
		ocf_log info SUCCESS
		exit $OCF_SUCCESS
	fi
	;;
  restart)
	$0 stop || exit $OCF_ERR_GENERIC
	$0 start || exit $OCF_ERR_GENERIC
	exit $OCF_SUCCESS
	;;
  monitor|status)
	# check if device is assembled 
	check_md_status || exit $OCF_ERR_GENERIC
	check_md_health && exit $OCF_SUCCESS || exit $OCF_ERR_GENERIC
	;;
  verify-all)
	# validation is done at the start of every run
	exit $OCF_SUCCESS
	;;
  *)
	echo "usage: $0 {start|stop|status|monitor|restart|meta-data|verify-all}"
	exit $OCF_ERR_UNIMPLEMENTED
	;;
esac

exit $rv
