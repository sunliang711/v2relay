#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
this="$(cd $(dirname $rpath) && pwd)"
cd "$this"

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 5)
        bold=$(tput bold)
reset=$(tput sgr0)
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
install(){

    if [ ! -e /usr/bin/time ];then
        echo "need /usr/bin/time"
        runAsRoot "apt install time -y" || { echo " install time error!"; exit 1; }
    fi
    _build
    # msg is made by 'figlet'
    cat msg
    bash download.sh || { echo "Download v2ray failed!"; exit 1; }
    sed -e "s|V2RAY|${this}/Linux/v2ray|g" \
        -e "s|CONFIG|${this}/etc/config.json|g" \
        -e "s|USER|${user}|g" \
        -e "s|PRE|${this}/bin/port.sh addChain|g"  daemon/v2relay.service > /tmp/v2relay.service

    runAsRoot "mv /tmp/v2relay.service /etc/systemd/system/v2relay.service"
    echo "systemd service v2relay has been installed."

    sed -e "s|V2RAY|${this}/Linux/v2ray|g" \
        -e "s|USER|${user}|g" \
        -e "s|CONFIG|${this}/etc/backend.json|g"  daemon/v2backend.service > /tmp/v2backend.service
    runAsRoot "mv /tmp/v2backend.service /etc/systemd/system/v2backend.service"
    echo "systemd service v2backend has been installed."

    echo "add ${this}/bin to PATH manually"
    echo "add crontab job"
    echo "Note: please enable no password to run sudo if you are not root"
    (crontab -l 2>/dev/null;echo "0 * * * * ${this}/bin/port.sh saveHour") | crontab -
    (crontab -l 2>/dev/null;echo "59 23 * * * ${this}/bin/port.sh saveDay") | crontab -

    (crontab -l 2>/dev/null;echo "*/2 * * * * ${this}/bin/v2relay.sh selectBest >>/tmp/selectBest.log 2>&1") | crontab -

    echo "add ${this}/bin to PATH manually"
}

_build(){
    cd /tmp
    if [ ! -d fetchSubscription ];then
        git clone https://gitee.com/sunliang711/fetchSubscription || { echo "clone fetchSubscription error "; exit 1; }
    fi
    cd fetchSubscription && bash ./build.sh build && cp fetch v2ray.tmpl ${this}/bin
    cd ${this}
}

uninstall(){
    ./bin/v2relay.sh stop
    rm ./bin/fetch
    rm ./bin/v2ray.tmpl
    runAsRoot "rm /etc/systemd/system/v2relay.service"
    runAsRoot "rm /etc/systemd/system/v2backend.service"
}



###############################################################################
# write your code above
###############################################################################
function help(){
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | perl -lne "print if /^\t[^_]/"
}

case "$1" in
     ""|-h|--help|help)
        help
        ;;
    *)
        "$@"
esac
