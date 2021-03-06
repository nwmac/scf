#used for initial config
MAIN_CONFIG="90-vcap.conf"
RSYSLOG_CONF_DIR="/etc/rsyslog.d"

#used for adding individual logs
BACKUP_WATCH_DIR=/var/vcap/sys/log #in case no ENV variable is set for RSYSLOG_FORWARDER_WATCH_DIR
RSYSLOG_CONF_PREFIX=91-vcap
RSYSLOG_CONF_DIR=/etc/rsyslog.d
IGNORE_DIR="gocode"
TARGET_NAME=
TARGET_BASENAME=

SCRIPT_FILE=/usr/sbin/forward_logfiles.sh
PB_OUT=/var/log/pb.out

if [ ! -f $SCRIPT_FILE ]; then
	echo "#log forwarding script" > $PB_OUT
fi

if [ -z "${RSYSLOG_FORWARDER_WATCH_DIR:-}" ]; then
        RSYSLOG_FORWARDER_WATCH_DIR=$BACKUP_WATCH_DIR
        echo "RSYSLOG_FORWARDER_WATCH_DIR not set. Using default $BACKUP_WATCH_DIR" >> $PB_OUT
fi

if [ ! -d "$RSYSLOG_FORWARDER_WATCH_DIR" ]; then
        echo "$RSYSLOG_FORWARDER_WATCH_DIR is not a valid directory" >> $PB_OUT
fi

if [ -z "$HCP_FLIGHTRECORDER_HOST" -a -z "$HCF_LOG_HOST" ]; then
    echo "Neither HCP_FLIGHTRECORDER_HOST nor HCF_LOG_HOST are set" >> $PB_OUT
    exit 0
fi

if [ -z $HCP_FLIGHTRECORDER_PORT ]; then
    HCP_FLIGHTRECORDER_PORT=514
fi

if [ -z "$HCF_LOG_HOST" ]; then
    HCF_LOG_HOST=${HCP_FLIGHTRECORDER_HOST}
fi

if [ -z "$HCF_LOG_PORT" ]; then
    HCF_LOG_PORT=${HCP_FLIGHTRECORDER_PORT}
fi

_HCF_LOG_CONFIG=$HCF_LOG_HOST:$HCF_LOG_PORT

function appendToCron {
	echo appending to cron
        crontab -l > tempcrontab
        echo "export _HCF_LOG_CONFIG=$HCF_LOG_CONFIG" >> $SCRIPT_FILE
        echo "export RSYSLOG_FORWARDER_WATCH_DIR=$RSYSLOG_FORWARDER_WATCH_DIR" >> $SCRIPT_FILE
        echo "export HCP_FLIGHTRECORDER_HOST=$HCP_FLIGHTRECORDER_HOST" >> $SCRIPT_FILE
        echo "export HCP_FLIGHTRECORDER_PORT=$HCP_FLIGHTRECORDER_PORT" >> $SCRIPT_FILE
        echo "export HCF_LOG_HOST=$HCF_LOG_HOST" >> $SCRIPT_FILE
        echo "export HCF_LOG_PORT=$HCF_LOG_PORT" >> $SCRIPT_FILE
        echo "export HCF_LOG_PREFIX=$HCF_LOG_PREFIX" >> $SCRIPT_FILE
        echo "export HCF_LOG_PROTOCOL=$HCF_LOG_PROTOCOL" >> $SCRIPT_FILE
        cat $0 >> $SCRIPT_FILE
        echo "*/1 * * * * bash $SCRIPT_FILE >> /dev/null 2>&1" >> tempcrontab
        crontab tempcrontab
}

#check if cron has something in it
if crontab -l &>/dev/null ; then
        #put the script in cron if it is not there already
        if ! { crontab -l | grep forward_logfiles.sh ; } ; then
                appendToCron
        fi
else
        echo "#creating cron conf as it does not exist yet" >> $PB_OUT
        appendToCron
fi


# create the file that will forward all messages to the configured log
# destination, flight recorder or other
function initialConfig {

	case ${HCF_LOG_PROTOCOL} in
	    udp)
		HCF_LOG_PREFIX=
		;;
	    tcp)
		HCF_LOG_PREFIX=@
		;;
	    *)
                echo "Rsyslog forwarder: Bad protocol ${...}, could not create $MAIN_CONFIG in $RSYSLOG_CONF_DIR" >> $PB_OUT
                exit 0
		;;
	esac

        if ! cat <<-EOF | sed 's@^\s*@@' >$RSYSLOG_CONF_DIR/$MAIN_CONFIG ; then
                module(load="imfile" mode="polling")
                \$template RFC5424Format,"<13>%protocol-version% 2016-07-20T09:03:00.329650+00:00 %HOSTNAME% %app-name% - - - %msg%\n"
                \$ActionFileDefaultTemplate RFC5424Format
                \$RepeatedMsgReduction on
                \$ActionQueueType LinkedList
                *.* @${HCF_LOG_PREFIX}${HCF_LOG_HOST}:${HCF_LOG_PORT}
                :app-name, contains, "vcap" ${HOME}
	EOF
                echo "Rsyslog forwarder: Could not create $MAIN_CONFIG in $RSYSLOG_CONF_DIR" >> $PB_OUT
                exit 0
        fi

        if [[ ! -f "$RSYSLOG_CONF_DIR/$MAIN_CONFIG" ]]; then
                echo "Rsyslog forwarder: File $MAIN_CONFIG not found in $RSYSLOG_CONF_DIR" >> $PB_OUT
                exit 0
        fi
}

# check if more logs to be monitored by rsyslog have come into existence since the last run
function searchTargetDir {
        filesAdded=1
        for file in $1/*
        do
                if [ -d $file ]; then
                        ignored=false
                        for ignore in $IGNORE_DIR
                        do
                                if [[ $file == $RSYSLOG_FORWARDER_WATCH_DIR/$ignore ]]; then
                                        echo "Ignoring $file directory"
                                        ignored=true
                                fi
                        done;
                        if [ $ignored == false ]; then
                                if searchTargetDir $file; then
                                        filesAdded=0
                                fi
                        fi
                else
                        if [ "${file: -4}" == ".log" ]; then
                                targetName $file
                                if checkConfigExists $file; then
                                        echo $TARGET_NAME exists
                                else
                                        echo "Creating $TARGET_NAME"
                                        createTargetConf $file
                                        filesAdded=0
                                fi
                        fi
                fi
        done
        return $filesAdded
}

#Create the rsyslog configuration file inside rsysconf.d
function createTargetConf {
        # We need to strip leading whitespace introduced by the heredoc (because
        # it doesn't strip leading spaces, just tabs)
        cat <<-EOF | sed 's@^\s*@@' >${TARGET_NAME}
            \$InputFileName ${1}
            \$InputFileTag vcap-${TARGET_BASENAME}
            \$InputFileStateFile ${TARGET_BASENAME}_state
            \$InputFileFacility local7
            \$InputRunFileMonitor
	EOF
}

function targetName {
        filename=$(basename $1)
        TARGET_BASENAME="${filename%.*}"
}

function checkConfigExists {
        TARGET_NAME=$RSYSLOG_CONF_DIR/$RSYSLOG_CONF_PREFIX-$TARGET_BASENAME.conf
        if [ -f $TARGET_NAME ]; then
                return 0
        else
                return 1
        fi
}

#check if the forwarding conf is set up
if [ ! -f $RSYSLOG_CONF_DIR/$MAIN_CONFIG ]; then
      echo creating initial config for forwarding
      initialConfig
else
      echo initial config for forwarding exists
fi

#make sure that configurations (per log-file) are added to the rsyslog.d folder
if searchTargetDir $RSYSLOG_FORWARDER_WATCH_DIR; then
        if test -r /var/run/rsyslog.pid; then
                if test -d /proc/$(cat /var/run/rsyslog.pid); then
                        service rsyslog restart
                fi
        fi
fi
