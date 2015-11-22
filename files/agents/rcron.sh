#!/bin/bash

#
# rcron agent
#
#
# Copyright (C) 2014 Jakov Sosic <jsosic@gmail.com>.
# All rights reserved.
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

export LC_ALL=C
export LANG=C
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

. $(dirname $0)/ocf-shellfuncs
. $(dirname $0)/utils/config-utils.sh
. $(dirname $0)/utils/messages.sh
. $(dirname $0)/utils/ra-skelet.sh
. $(dirname $0)/utils/member_util.sh

rv=0

verify_all()
{
        clog_service_verify $CLOG_INIT

        if [ -z "$OCF_RESKEY_name" ]; then
                clog_service_verify $CLOG_FAILED "Invalid Name Of Service"
                return $OCF_ERR_ARGS
        fi

        if [ -z "$OCF_RESKEY_state_file" ]; then
                clog_check_file_exist $CLOG_FAILED_INVALID "$OCF_RESKEY_state_file"
                clog_service_verify $CLOG_FAILED
                return $OCF_ERR_ARGS
        fi

        clog_service_verify $CLOG_SUCCEED

        return 0
}

# checks wether rcron is active on local node, returns 0 if active
status_check_state_file()
{
	[ ! -f ${OCF_RESKEY_state_file} ] && return $OCF_ERR_GENERIC
        /bin/grep -q active $OCF_RESKEY_state_file
        [ $? -eq 0 ] && return $OCF_SUCCESS || return $OCF_ERR_GENERIC
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

# checks status of rcron on remote nodes, returns 0 if inactive
check_remote_status(){
        # if remote checks are disabled return success
        [ $OCF_RESKEY_ssh_check -ne 1 ] && return $OCF_SUCCESS

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
                        /usr/bin/ssh $node "/bin/grep -q active ${OCF_RESKEY_state_file}"
                        if [ $? -eq 0 ]; then
                                ocf_log err "rcron: Improper setup detected"
                                ocf_log err "* rcron is active on node \"$node\""
                                return $OCF_ERR_GENERIC
                        fi
                fi
        done

        # rcron is not active anywhere
        return $OCF_SUCCESS
}

start()
{
	clog_service_start $CLOG_INIT
	
	echo 'active' > $OCF_RESKEY_state_file

	if [ $? -ne 0 ]; then
		clog_service_start $CLOG_FAILED
		return $OCF_ERR_GENERIC
	fi
	
	clog_service_start $CLOG_SUCCEED
	
	return 0;
}

stop()
{
        clog_service_stop $CLOG_INIT

	echo 'passive' > $OCF_RESKEY_state_file

        if [ $? -ne 0 ]; then
                clog_service_stop $CLOG_FAILED
                return $OCF_ERR_GENERIC
        fi

        clog_service_stop $CLOG_SUCCEED
        return 0;
}

status()
{
        clog_service_status $CLOG_INIT

        status_check_state_file "$OCF_RESKEY_state_file"

        if [ $? -ne 0 ]; then
                clog_service_status $CLOG_FAILED "$OCF_RESKEY_state_file"
                return $OCF_ERR_GENERIC
        fi

        clog_service_status $CLOG_SUCCEED
        return 0
}

if [ "$1" != "meta-data" ]; then
	# verify setup
	verify_all          || exit $?
	check_remote_status || exit $?
fi;

case $1 in
        meta-data)
                cat `echo $0 | sed 's/^\(.*\)\.sh$/\1.metadata/'`
                exit 0
                ;;
        validate-all)
                verify_all
                exit $?
                ;;
        start)
                verify_all && start
                exit $?
                ;;
        stop)
                verify_all && stop
                exit $?
                ;;
        status|monitor)
                verify_all
                status
                exit $?
                ;;
        restart)
                verify_all
                stop
                start
                exit $?
                ;;
        *)
                echo "Usage: $0 {start|stop|status|monitor|restart|meta-data|validate-all}"
                exit $OCF_ERR_UNIMPLEMENTED
                ;;
esac

exit $rv
