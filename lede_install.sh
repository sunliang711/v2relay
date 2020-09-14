#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
this="$(cd $(dirname $rpath) && pwd)"
cd "$this"

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

function runAsRoot(){
    verbose=0
    while getopts ":v" opt;do
        case "$opt" in
            v)
                verbose=1
                ;;
            \?)
                echo "Unknown option: \"$OPTARG\""
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))
    cmd="$@"
    if [ -z "$cmd" ];then
        echo "${red}Need cmd${reset}"
        exit 1
    fi

    if [ "$verbose" -eq 1 ];then
        echo "run cmd:\"${red}$cmd${reset}\" as root."
    fi

    if (($EUID==0));then
        sh -c "$cmd"
    else
        if ! command -v sudo >/dev/null 2>&1;then
            echo "Need sudo cmd"
            exit 1
        fi
        sudo sh -c "$cmd"
    fi
}
###############################################################################
# write your code below (just define function[s])
# function with 'function' is hidden when run help, without 'function' is show
###############################################################################
# TODO
function check(){
    if ! grep -qi 'koolshare mod v2.35' /etc/os-release;then
        echo "Warning: Your OS is not koolshare lede v2.35"
    fi
}

install(){
    #msg is made by 'figlet'
    cat msg

    bash download.sh || { echo "Download v2ray failed!"; exit 1; }

    #
    sed -e "s|V2RAY|${this}/Linux/v2ray|g" \
        -e "s|CONFIG|${this}/etc/config.json|g" \
        daemon/v2relay >/tmp/v2relay
    chmod +x /tmp/v2relay
    mv /tmp/v2relay /etc/init.d/v2relay
    /etc/init.d/v2relay enable
    /etc/init.d/v2relay start


    # echo "add crontab job"
    # (crontab -l 2>/dev/null;echo "0 * * * * $this/bin/port.sh saveHour") | crontab -
    # (crontab -l 2>/dev/null;echo "59 23 * * * $this/bin/port.sh saveDay") | crontab -

    # echo "add ${this}/bin to PATH manually"
}

uninstall(){
    # runAsRoot "rm /etc/systemd/system/v2relay.service"
    echo TODO
}



###############################################################################
# write your code above
###############################################################################
function help(){
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    perl -lne 'print "\t$1" if /^\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | grep -v runAsRoot
}

case "$1" in
     ""|-h|--help|help)
        help
        ;;
    *)
        "$@"
esac
