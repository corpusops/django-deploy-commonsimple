#!/bin/bash
SDEBUG=${SDEBUG-}
DEBUG=${DEBUG:-${SDEBUG-}}
# activate shell debug if SDEBUG is set
VCOMMAND=""
DASHVCOMMAND=""
if [[ -n $SDEBUG ]];then set -x; VCOMMAND="v"; DASHVCOMMAND="-v";fi
SCRIPTSDIR="$(dirname $(readlink -f "$0"))"
ODIR=$(pwd)
cd "$SCRIPTSDIR/.."
TOPDIR="$(pwd)"
BASE_DIR="${BASE_DIR:-${TOPDIR}}"

# now be in stop-on-error mode
set -e

# export back the gateway ip as a host if ip is available in container
if ( ip -4 route list match 0/0 &>/dev/null );then
    ip -4 route list match 0/0 | awk '{print $3" host.docker.internal"}' >> /etc/hosts
fi

PYCHARM_DIRS="${PYCHARM_DIRS:-"/opt/pycharm /opt/.pycharm /opt/.pycharm_helpers"}"
OPYPATH="${PYTHONPATH-}"
for i in $PYCHARM_DIRS;do if [ -e "$i" ];then IMAGE_MODE="${FORCE_IMAGE_MODE-pycharm}";break;fi;done

# load locales & default env while preserving original $PATH
export OPATH=$PATH
for i in /etc/environment /etc/default/locale;do if [ -e $i ];then . $i;fi;done
export PATH=$OPATH

# load virtualenv if present
for VENV in "$BASE_DIR/venv" "$BASE_DIR/venv";do if [ -e "$VENV" ];then export VENV;. "$VENV/bin/activate";break;fi;done

SRC_DIR="${SRC_DIR:-${TOPDIR}}"
if [ -e src ];then SRC_DIR="$TOPDIR/src";fi


DEFAULT_IMAGE_MODE=gunicorn
NO_GUNICORN=${NO_GUNICORN-}
if [[ -n $NO_GUNICORN ]];then
    # retro compat with old setups
    DEFAULT_IMAGE_MODE=fg
fi
export IMAGE_MODE=${IMAGE_MODE:-${DEFAULT_IMAGE_MODE}}
SKIP_STARTUP_DB=${SKIP_STARTUP_DB-}
SKIP_SYNC_DOCS=${SKIP_SYNC_DOCS-}
IMAGE_MODES="(shell|cron|gunicorn|fg|celery_worker|celery_beat)"
IMAGE_MODES_MIGRATE="(gunicorn|fg)"
NO_START=${NO_START-}
DJANGO_CONF_PREFIX="${DJANGO_CONF_PREFIX:-"DJANGO__"}"
DEFAULT_NO_MIGRATE=1
DEFAULT_NO_COMPILE_MESSAGES=
DEFAULT_NO_STARTUP_LOGS=
DEFAULT_NO_COLLECT_STATIC=
if ( echo $IMAGE_MODE|grep -E -iq "$IMAGE_MODES_MIGRATE" );then
    DEFAULT_NO_MIGRATE=
fi
if [[ -n $@ ]];then
    IMAGE_MODE=shell
    DEFAULT_NO_MIGRATE=1
    DEFAULT_NO_COMPILE_MESSAGES=1
    DEFAULT_NO_COLLECT_STATIC=1
    DEFAULT_NO_STARTUP_LOGS=1
fi
NO_MIGRATE=${NO_MIGRATE-$DEFAULT_NO_MIGRATE}
NO_STARTUP_LOGS=${NO_STARTUP_LOGS-$DEFAULT_NO_STARTUP_LOGS}
NO_COMPILE_MESSAGES=${NO_COMPILE_MESSAGES-$DEFAULT_NO_COMPILE_MESSAGES}
NO_COLLECT_STATIC=${NO_COLLECT_STATIC-$DEFAULT_NO_COLLECT_STATIC}
NO_IMAGE_SETUP="${NO_IMAGE_SETUP:-"1"}"
SKIP_IMAGE_SETUP="${KIP_IMAGE_SETUP:-""}"
FORCE_IMAGE_SETUP="${FORCE_IMAGE_SETUP:-"1"}"
DO_IMAGE_SETUP_MODES="${DO_IMAGE_SETUP_MODES:-"fg|gunicorn"}"
export PIP_SRC=${PIP_SRC:-${BASE_DIR}/pipsrc}
export LOCAL_DIR="${LOCAL_DIR:-/local}"
NO_PIPENV_INSTALL=${NO_PIPENV_INSTALL-1}
PIPENV_INSTALL_ARGS="${PIPENV_INSTALL_ARGS-"--ignore-pipfile"}"

FINDPERMS_PERMS_DIRS_CANDIDATES="${FINDPERMS_PERMS_DIRS_CANDIDATES:-"public private"}"
FINDPERMS_OWNERSHIP_DIRS_CANDIDATES="${FINDPERMS_OWNERSHIP_DIRS_CANDIDATES:-"$LOCAL_DIR public private data"}"

export HISTFILE="${LOCAL_DIR}/.bash_history"
export PSQL_HISTORY="${LOCAL_DIR}/.psql_history"
export MYSQL_HISTFILE="${LOCAL_DIR}/.mysql_history"
export IPYTHONDIR="${LOCAL_DIR}/.ipython"

export TMPDIR="${TMPDIR:-/tmp}"
export STARTUP_LOG="${STARTUP_LOG:-$TMPDIR/django_startup.log}"
export APP_TYPE="${APP_TYPE:-django}"
export APP_USER="${APP_USER:-$APP_TYPE}"
export HOST_USER_UID="${HOST_USER_UID:-$(id -u $APP_USER)}"
export INIT_HOOKS_DIR="${INIT_HOOKS_DIR:-${BASE_DIR}/sys/scripts/hooks}"
export APP_GROUP="$APP_USER"
export EXTRA_USER_DIRS="${EXTRA_USER_DIRS-}"
export USER_DIRS="${USER_DIRS:-". src public/media data /logs/cron $LOCAL_DIR ${EXTRA_USER_DIRS}"}"
export SHELL_USER="${SHELL_USER:-${APP_USER}}" SHELL_EXECUTABLE="${SHELL_EXECUTABLE:-/bin/bash}"

# django variables
export GUNICORN_CLASS=${GUNICORN_CLASS:-sync}
export GUNICORN_EXTRA_ARGS="${GUNICORN_EXTRA_ARGS-}"
export GUNICORN_WORKERS=${GUNICORN_WORKERS:-4}
export DJANGO_WSGI=${DJANGO_WSGI:-project.wsgi}
export DJANGO_LISTEN=${DJANGO_LISTEN:-"0.0.0.0:8000"}

# Celery variables
# export CELERY_SCHEDULER=${CELERY_SCHEDULER:-celery.beat.PersistentScheduler}
export CELERY_SCHEDULER=${CELERY_SCHEDULER:-django_celery_beat.schedulers:DatabaseScheduler}
export CELERY_LOGLEVEL=${CELERY_LOGLEVEL:-info}
export CELERY_WORKER_POOL=${CELERY_WORKER_POOL:-prefork}
export CELERY_CONCURRENCY=${CELERY_CONCURRENCY-}
export DJANGO_CELERY=${DJANGO_CELERY:-project.celery:app}
export DJANGO_CELERY_BROKER="${DJANGO_CELERY_BROKER:-amqp}"
export DJANGO_CELERY_HOST="${DJANGO_CELERY_HOST:-celery-broker}"
export DJANGO_CELERY_VHOST="${DJANGO_CELERY_VHOST:-}"
if ( echo "$DJANGO_CELERY_BROKER" | grep -E -q "rabbitmq|amqp" );then
    burl="amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@$DJANGO_CELERY_HOST/$DJANGO_CELERY_VHOST/"
elif [[ "$DJANGO_CELERY_BROKER" = "redis" ]];then
    burl="redis://$DJANGO_CELERY_HOST/"
fi
export DJANGO__CELERY_BROKER_URL="${DJANGO__CELERY_BROKER_URL:-$burl}"

# forward console integration
export TERM="${TERM-}" COLUMNS="${COLUMNS-}" LINES="${LINES-}"

debuglog() { if [[ -n "$DEBUG" ]];then echo "$@" >&2;fi }
log() { echo "$@" >&2; }
die() { log "$@";exit 1; }
vv() { log "$@";"$@"; }

# Regenerate egg-info & be sure to have it in site-packages
regen_egg_info() {
    local f="$1"
    if [ -e "$f" ];then
        local e="$(dirname "$f")"
        echo "Reinstalling egg-info in: $e" >&2
        if ! ( cd "$e" && gosu $APP_USER python setup.py egg_info >/dev/null 2>&1; );then
            ( cd "$e" && gosu $APP_USER python setup.py egg_info 2>&1; )
        fi
    fi
}

#  shell: Run interactive shell inside container
_shell() {
    exec gosu ${user:-$APP_USER} $SHELL_EXECUTABLE -$([[ -n ${SSDEBUG:-$SDEBUG} ]] && echo "x" )elc "${@:-${SHELL_EXECUTABLE}}"
}

#  configure: generate configs from template at runtime
configure() {
    if [[ -n $NO_CONFIGURE ]];then return 0;fi
    for i in $USER_DIRS;do
        if [ ! -e "$i" ];then mkdir -p "$i" >&2;fi
        chown $APP_USER:$APP_GROUP "$i"
    done
    for i in $HISTFILE $MYSQL_HISTFILE $PSQL_HISTORY;do if [ ! -e "$i" ];then touch "$i";fi;done
    for i in $IPYTHONDIR;do if [ ! -e "$i" ];then mkdir -pv "$i";fi;done
    for i in $HISTFILE $MYSQL_HISTFILE $PSQL_HISTORY $IPYTHONDIR;do chown -Rf $APP_USER "$i";done
    if (find /etc/sudoers* -type f >/dev/null 2>&1);then chown -Rf root:root /etc/sudoers*;fi
    # reinstall in develop any missing editable dep in Pipenv
    if [ -e Pipfile ] && ( grep -E -q  "editable\s*=\s*true" Pipfile ) && [[ -z "$(ls -1 ${PIP_SRC}/ | grep -vi readme)" ]] && [[ "$NO_PIPENV_INSTALL" != "1" ]];then
        pipenv install $PIPENV_INSTALL_ARGS 1>&2
    fi
    # regenerate any setup.py found as it can be an egg mounted from a docker volume
    # without having a chance to be built
    while read f;do regen_egg_info "$f";done < <( \
        find "$TOPDIR/setup.py" "$TOPDIR/src" "$TOPDIR/lib" \
        -maxdepth 2 -mindepth 0 -name setup.py -type f 2>/dev/null; )
    # copy only if not existing template configs from common deploy project
    # and only if we have that common deploy project inside the image
    if [ ! -e etc ];then mkdir etc;fi
    for i in sys/etc local/*deploy-common/etc local/*deploy-common/sys/etc;do
        if [ -d $i ];then cp -rfnv $i/* etc >&2;fi
    done
    # install with envsubst any template file to / (eg: logrotate & cron file)
    for i in $(find etc -name "*.envsubst" -type f 2>/dev/null);do
        di="/$(dirname $i)" \
            && if [ ! -e "$di" ];then mkdir -pv "$di" >&2;fi \
            && cp "$i" "/$i" \
            && CONF_PREFIX="$DJANGO_CONF_PREFIX" confenvsubst.sh "/$i" \
            && rm -f "/$i"
    done
    # install wtih frep any template file to / (eg: logrotate & cron file)
    for i in $(find etc -name "*.frep" -type f 2>/dev/null);do
        d="$(dirname "$i")/$(basename "$i" .frep)" \
            && di="/$(dirname $d)" \
            && if [ ! -e "$di" ];then mkdir -pv "$di" >&2;fi \
            && echo "Generating with frep $i:/$d" >&2 \
            && frep "$i:/$d" --overwrite
    done
}

#  services_setup: when image run in daemon mode: pre start setup like database migrations, etc
services_setup() {
    if [[ -z $NO_IMAGE_SETUP ]];then
        if [[ -n $FORCE_IMAGE_SETUP ]] || ( echo $IMAGE_MODE | grep -E -q "$DO_IMAGE_SETUP_MODES" ) ;then
            debuglog "Force services_setup"
        else
            debuglog "No image setup" && return 0
        fi
    fi
    if [[ "$SKIP_IMAGE_SETUP" = "1" ]];then
        debuglog "Skip image setup" && return 0
    fi
    debuglog "doing services_setup"
    # alpine linux has /etc/crontabs/ and ubuntu based vixie has /etc/cron.d/
    if [ -e /etc/cron.d ] && [ -e /etc/crontabs ];then cp -fv /etc/crontabs/* /etc/cron.d >&2;fi
    # Run any migration
    if [[ -z ${NO_MIGRATE} ]];then
        ( cd $SRC_DIR && gosu $APP_USER ./manage.py migrate --noinput )
    fi
    # Compile gettext messages
    if [[ -z ${NO_COMPILE_MESSAGES} ]];then
        ( cd $SRC_DIR && gosu $APP_USER ./manage.py compilemessages )
    fi
    # Collect statics
    if [[ -z ${NO_COLLECT_STATIC} ]];then
        ( cd $SRC_DIR && gosu $APP_USER ./manage.py collectstatic --noinput )
    fi
}

# fixperms: basic file & ownership enforcement
fixperms() {
    if [[ -n $NO_FIXPERMS ]];then return 0;fi
	if [ "$(id -u $APP_USER)" != "$HOST_USER_UID" ];then
	    groupmod -g $HOST_USER_UID $APP_USER
	    usermod -u $HOST_USER_UID -g $HOST_USER_UID $APP_USER
	fi
    for i in /etc/{crontabs,cron.d} /etc/logrotate.d /etc/supervisor.d;do
        if [ -e $i ];then
            while read f;do
                chown -R root:root "$f"
                chmod 0640 "$f"
            done < <(find "$i" -type f)
        fi
    done
    for i in $USER_DIRS;do if [ -e "$i" ];then chown $APP_USER:$APP_GROUP "$i";fi;done
    while read f;do chmod 0755 "$f";done < \
        <(find $FINDPERMS_PERMS_DIRS_CANDIDATES -type d -not \( -perm 0755 2>/dev/null \) |sort)
    while read f;do chmod 0644 "$f";done < \
        <(find $FINDPERMS_PERMS_DIRS_CANDIDATES -type f -not \( -perm 0644 2>/dev/null \) |sort)
    while read f;do chown $APP_USER:$APP_USER "$f";done < \
        <(find $FINDPERMS_OWNERSHIP_DIRS_CANDIDATES \
          \( -type d -or -type f \) -and -not \( -user $APP_USER -and -group $APP_GROUP \) 2>/dev/null|sort)
}

#  usage: print this help
usage() {
    drun="docker run --rm -it <img>"
    echo "EX:
$drun [-e NO_COLLECT_STATIC=1] [-e NO_MIGRATE=1] [ -e FORCE_IMAGE_SETUP] [-e IMAGE_MODE=\$mode]
    docker run <img>
        run either django, cron, or celery beat|worker daemon
        (IMAGE_MODE: $IMAGE_MODES)

$drun \$args: run commands with the context ignited inside the container
$drun [ -e FORCE_IMAGE_SETUP=1] [ -e NO_IMAGE_SETUP=1] [-e SHELL_USER=\$ANOTHERUSER] [-e IMAGE_MODE=\$mode] [\$command[ \args]]
    docker run <img> \$COMMAND \$ARGS -> run command
    docker run <img> shell -> interactive shell
(default user: $SHELL_USER)
(default mode: $IMAGE_MODE)

If FORCE_IMAGE_SETUP is set: run migrate/collect static
If NO_IMAGE_SETUP is set: migrate/collect static is skipped, no matter what
If NO_START is set: start an infinite loop doing nothing (for dummy containers in dev)
"
  exit 0
}

do_fg() {
    cd $SRC_DIR && exec gosu $APP_USER ./manage.py runserver $DJANGO_LISTEN
}

execute_hooks() {
    local step="$1"
    local hdir="$INIT_HOOKS_DIR/${step}"
    shift
    if [ ! -d "$hdir" ];then return 0;fi
    while read f;do
        if ( echo "$f" | grep -E -q "\.sh$" );then
            debuglog "running shell hook($step): $f" && . "${f}"
        else
            debuglog "running executable hook($step): $f" && "$f" "$@"
        fi
    done < <(find "$hdir" -type f -executable 2>/dev/null | grep -E -iv readme | sort -V; )
}

# Run app preflight routines (layout, files sync to campanion volumes, migrations, permissions fix, etc.)
pre() {
    if [ -e "${BASE_DIR}/docs" ] && [[ -z "${SKIP_SYNC_DOCS}" ]];then
        rsync -az${VCOMMAND} "${BASE_DIR}/docs/" "${BASE_DIR}/outdocs/" --delete
    fi
    # wait for db to be avalaible (skippable with SKIP_STARTUP_DB)
    # come from https://github.com/corpusops/docker-images/blob/master/rootfs/bin/project_dbsetup.sh
    if [ "x$SKIP_STARTUP_DB" = "x" ];then project_dbsetup.sh;fi
    execute_hooks pre "$@"
    configure
    execute_hooks afterconfigure "$@"
    # fixperms may have to be done on first run
    if ! ( services_setup );then
        fixperms
        execute_hooks beforeservicessetup "$@"
        services_setup
    fi
    execute_hooks beforesefixperms "$@"
    fixperms
    execute_hooks post "$@"
}

if ( echo $1 | grep -E -q -- "--help|-h|help" );then usage;fi

if [[ -n ${NO_START-} ]];then
    while true;do echo "start skipped" >&2;sleep 65535;done
    exit $?
fi

# only display startup logs when we start in daemon mode and try to hide most when starting an (eventually interactive) shell.
if ! ( echo "$NO_STARTUP_LOGS" | grep -E -iq "^(no?)?$" );then if !( pre >"$STARTUP_LOG" 2>&1 );then cat "$STARTUP_LOG">&2;die "preflight startup failed";fi;else pre;fi;

if [[ $IMAGE_MODE == "pycharm" ]];then
    cmdargs="$@"
    for i in ${PYCHARM_DIRS};do if [ -e "$i" ];then chown -Rf $APP_USER "$i";fi;done
    exec gosu $APP_USER bash -lc "set -e;cd $ODIR;export PYTHONPATH=\"$OPYPATH:\${PYTHONPATH-}·\";python $cmdargs"
fi

if [[ "${IMAGE_MODE}" != "shell" ]]; then
    if ! ( echo $IMAGE_MODE | grep -E -q "$IMAGE_MODES" );then die "Unknown image mode ($IMAGE_MODES): $IMAGE_MODE";fi
    log "Running in $IMAGE_MODE mode"
    if [ -e "$STARTUP_LOG" ];then cat "$STARTUP_LOG";fi
    if [[ "$IMAGE_MODE" = "fg" ]]; then
        do_fg
    else
        cfg="/etc/supervisor.d/$IMAGE_MODE"
        if [ ! -e $cfg ];then die "Missing: $cfg";fi
        SUPERVISORD_CONFIGS="rsyslog $cfg" exec supervisord.sh
    fi
else
    if [[ "${1-}" = "shell" ]];then shift;fi
    # retrocompat with old images
    cmd="$@"
    if ( echo "$cmd" | grep -E -q "tox.*/bin/sh -c tests" );then
        cmd=$( echo "${cmd}"|sed -r -e "s/-c tests/-exc '.\/manage.py test/" -e "s/$/'/g" )
    fi
    execute_hooks beforeshell "$@"
    ( cd $SRC_DIR && user=$SHELL_USER _shell "$cmd" )
fi
