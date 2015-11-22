#!/bin/bash

#
# rsyslog agent
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

export LC_ALL=C
export LANG=C
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

. $(dirname $0)/ocf-shellfuncs
. $(dirname $0)/utils/config-utils.sh
. $(dirname $0)/utils/messages.sh
. $(dirname $0)/utils/ra-skelet.sh

declare RSYSLOG=/sbin/rsyslogd
declare RSYSLOG_pid_dir="`generate_name_for_pid_dir`"
declare RSYSLOG_conf_dir="`generate_name_for_conf_dir`"
declare RSYSLOG_pid_file="$RSYSLOG_pid_dir/rsyslogd.pid"
declare RSYSLOG_gen_config_file="$RSYSLOG_conf_dir/rsyslog.conf"
declare RSYSLOG_kill_timeout="3"

verify_all()
{
        clog_service_verify $CLOG_INIT

        if [ -z "$OCF_RESKEY_name" ]; then
                clog_service_verify $CLOG_FAILED "Invalid Name Of Service"
                return $OCF_ERR_ARGS
        fi

        if [ -z "$OCF_RESKEY_service_name" ]; then
                clog_service_verify $CLOG_FAILED_NOT_CHILD
                return $OCF_ERR_ARGS
        fi

        if [ -z "$OCF_RESKEY_config_file" ]; then
                clog_check_file_exist $CLOG_FAILED_INVALID "$OCF_RESKEY_config_file"
                clog_service_verify $CLOG_FAILED
                return $OCF_ERR_ARGS
        fi

        if [ ! -r "$OCF_RESKEY_config_file" ]; then
                clog_check_file_exist $CLOG_FAILED_NOT_READABLE $OCF_RESKEY_config_file
                clog_service_verify $CLOG_FAILED
                return $OCF_ERR_ARGS
        fi

        clog_service_verify $CLOG_SUCCEED

        return 0
}

generate_config_file()
{
        declare original_file="$1"
        declare generated_file="$2"
        declare ip_addresses="$3"

        if [ -f "$generated_file" ]; then
                sha1_verify "$generated_file"
                if [ $? -ne 0 ]; then
                        clog_check_sha1 $CLOG_FAILED
                        return 0
                fi
        fi

        clog_generate_config $CLOG_INIT "$original_file" "$generated_file"

        generate_configTemplate "$generated_file" "$1"

        echo '### Start of resource agent generated part' >> "$generated_file"
        echo '# Provides UDP syslog reception' >> "$generated_file"
        echo '$ModLoad imudp' >> "$generated_file"
        echo >> "$generated_file"
        echo '### end of resource agent generated part' >> "$generated_file"
        echo >> "$generated_file"

        sed 's/^[[:space:]]*$ModLoad\(.*imudp.*\)/### $ModLoad \1/i;s/^[[:space:]]*$UDPServer\(.*\)/### $UDPServer\1/i' < "$original_file" >> "$generated_file"

        echo '### Start of resource agent generated part' >> "$generated_file"
        for i in $ip_addresses; do
                i=`echo $i | sed -e 's/\/.*$//'`
                echo '# Provides UDP syslog reception' >> "$generated_file"
                echo "\$UDPServerAddress ${i}" >> "$generated_file"
                echo '$UDPServerRun 514' >> "$generated_file"
        done
        echo '### end of resource agent generated part' >> "$generated_file"

        sha1_addToFile "$generated_file"
        clog_generate_config $CLOG_SUCCEED "$original_file" "$generated_file"

        return 0;
}

start()
{
	clog_service_start $CLOG_INIT
	
	create_pid_directory
	create_conf_directory "$RSYSLOG_conf_dir"
	check_pid_file "$RSYSLOG_pid_file"
	
	if [ $? -ne 0 ]; then
	       clog_check_pid $CLOG_FAILED "$RSYSLOG_pid_file"
	       clog_service_start $CLOG_FAILED
	       return $OCF_ERR_GENERIC
	fi

	clog_looking_for $CLOG_INIT "IP Addresses"

	get_service_ip_keys "$OCF_RESKEY_service_name"
	ip_addresses=`build_ip_list`

	if [ -z "$ip_addresses" ]; then
		clog_looking_for $CLOG_FAILED_NOT_FOUND "IP Addresses"
		return $OCF_ERR_GENERIC
	fi
	
	clog_looking_for $CLOG_SUCCEED "IP Addresses"


	generate_config_file "$OCF_RESKEY_config_file" "$RSYSLOG_gen_config_file" "$ip_addresses"
	
	$RSYSLOG -i "$RSYSLOG_pid_file" $OCF_RESKEY_options -f "$RSYSLOG_gen_config_file"

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

        ## Send -KILL signal immediately
        stop_generic_sigkill "$RSYSLOG_pid_file" "$RSYSLOG_kill_timeout"

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

        status_check_pid "$RSYSLOG_pid_file"

        if [ $? -ne 0 ]; then
                clog_service_status $CLOG_FAILED "$RSYSLOG_pid_file"
                return $OCF_ERR_GENERIC
        fi

        clog_service_status $CLOG_SUCCEED
        return 0
}

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
