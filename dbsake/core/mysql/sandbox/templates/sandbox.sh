#!/bin/bash

### BEGIN INIT INFO
# Provides: mysql-sandbox
# Required-Start: $local_fs $network $remote_fs
# Required-Stop: $local_fs $network $remote_fs
# Default-Start:  2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: start and stop a mysql sandboxed instance
# Description: Start mysql sandboxed instance setup by dbsake
### END INIT INFO

## Generated by: dbsake v{{__dbsake_version__}}

NAME=${0##*/}

START_TIMEOUT=300
STOP_TIMEOUT=300

version_and_comment="{{distribution.version}} {{distribution.version.comment}}"
version="{{distribution.version}}"

basedir={{distribution.basedir}}
defaults_file={{defaults_file}}
# mysql utilities used by this script
mysqld_safe={{distribution.mysqld_safe}}
mysql={{distribution.mysql}}
my_print_defaults=${basedir}/bin/my_print_defaults


# read an option from the mysql option file
_mysqld_option() {
    option=${1//-/_}
    option=${option//_/[_-]}
    shift
    sections="$@"
    ${my_print_defaults} --defaults-file=${defaults_file} ${sections} | \
        sed -n -e "s/^--${option}=//p" | tail -n1
}

sandbox_start() {
    if sandbox_status >/dev/null
    then
	echo "sandbox is already started"
        return 0
    fi
    echo -n "Starting sandbox: "
    # close stdin (0) and redirect stdout/stderr to /dev/null
    mysqld_safe_args="--defaults-file=$defaults_file --ledir='{{ distribution.libexecdir }}'"
    MY_BASEDIR_VERSION=${basedir} \
        nohup $mysqld_safe $mysqld_safe_args "$@" 0<&- &>/dev/null &
    local start_timeout=${START_TIMEOUT}
    until sandbox_status >/dev/null || [[ $start_timeout -le 0 ]]
    do
      kill -0 $! &>/dev/null || break
      echo -n "."
      sleep 1
      (( start_timeout-- ))
    done
    sandbox_status >/dev/null
    ret=$?
    [[ $ret -eq 0 ]] && echo "[OK]" || echo "[FAILED]"
    return $ret
}

sandbox_status() {
    pidfile=$(_mysqld_option pid-file mysqld mysqld_safe)
    if [[ -s "${pidfile}" && $(ps ho comm $(cat ${pidfile})) == mysqld ]]
    then
        { pid=$(<"${pidfile}"); } 2>/dev/null
    fi
    [[ -n "${pid}" ]] && kill -0 "${pid}" &>/dev/null
    ret=$?
    [[ $ret -eq 0 ]] && echo "mysqld ($pid) is running." || echo "mysqld is not running"
    return $ret
}

sandbox_stop() {
    pidfile=$(_mysqld_option pid-file mysqld mysqld_safe)
    if [[ -s "${pidfile}" ]]
    then
        { pid=$(<"${pidfile}"); } 2>/dev/null
    fi

    if [[ -z "$pid" ]]
    then
        echo "sandbox is already stopped"
        return 0
    fi

    echo -n "Stopping sandbox: "
    kill -TERM "$pid"
    local stop_timeout=${STOP_TIMEOUT}
    until [[ $stop_timeout -le 0 ]]
    do
        kill -0 "$pid" &>/dev/null || break
        echo -n "."
        sleep 1
        (( stop_timeout-- ))
    done
    ! kill -0 "$pid" &>/dev/null
    ret=$?
    [[ $ret -eq 0 ]] && echo "[OK]" || echo "[FAILED]"
    return $ret
}

case $1 in
    start)
        shift
        sandbox_start "$@"
        ;;
    status)
        sandbox_status
        ;;
    stop)
        sandbox_stop
        ;;
    restart|force-reload)
        shift
        sandbox_stop
        sandbox_start "$@"
        ;;
    condrestart|try-restart)
        sandbox_status &> /dev/null || exit 0
        sandbox_stop && start_start
        ;;
    reload)
        exit 3
        ;;
    ## Non-standard actions useful for sandbox interaction
    version)
        echo "${version_and_comment}"
        ;;
    metadata)
        echo "version         ${version_and_comment}"
        echo "sandbox datadir ${datadir}"
        echo "sandbox config  ${defaults_file}"
        echo "mysqld_safe     ${mysqld_safe}"
        echo "mysql           ${mysql}"
        echo "mysqldump       ${mysql}dump"
        echo "mysql_upgrade   ${mysql}_upgrade"
        ;;
    shell|mysql|use)
        shift
        MYSQL_PS1="mysql[sandbox]> " \
        MYSQL_HISTFILE="${basedir}/.mysql_history" \
        $mysql --defaults-file=$defaults_file "$@"
        ;;
    mysqldump)
        shift
        ${mysql}dump --defaults-file=$defaults_file "$@"
        ;;
    upgrade|mysql_upgrade)
        shift
        ${mysql}_upgrade --defaults-file=$defaults_file "$@"
        ;;
    install-service)
        name=${2:-mysql-$version}
        if [[ -e /etc/init.d/${name} ]]; then
            echo "/etc/init.d/${name} already exists. Aborting."
            exit 1
        fi

        if [[ $(type -p chkconfig) ]]; then
            install_cmd="$(type -p chkconfig) --add ${name} && $(type -p chkconfig) ${name} on"
        elif [[ $(type -p update-rc.d) ]]; then
            install_cmd="$(type -p update-rc.d) ${name} defaults"
        else
            echo "Neither chkconfig or update-rc.d was found. Not installing service."
            exit 1
        fi

        echo "+ $(type -p cp) ${0} /etc/init.d/${name}"
        $(type -p cp) ${0} /etc/init.d/${name} || { echo "copying init script failed"; exit 1; }
        echo "+ $install_cmd"
        eval $install_cmd || { echo "installing init script failed"; exit 1; }
        echo "Service installed in /etc/init.d/${name} and added to default runlevels"
        exit 0
        ;;
    *)
        echo "Usage: ${NAME} {start|stop|status|restart|condrestart|mysql|mysqldump|upgrade|install-service}"
        exit 2
        ;;
esac
exit $?
