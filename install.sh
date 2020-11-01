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
    ##TODO enableSudo for cron
    runAsRoot "./enableSudo.sh enable ${user}"

    if [ $? -ne 0 ];then
        echo "Enable sudo failed.exit!"
        exit 1
    fi

    if [ ! -e /usr/bin/time ];then
        echo "need /usr/bin/time"
        runAsRoot "apt install time -y" || { echo " install time error!"; exit 1; }
    fi
    _build
    # msg is made by 'figlet'
    cat msg
    bash download.sh || { echo "Download v2ray failed!"; exit 1; }
    sed -e "s|V2RAY|${this}/Linux/v2ray|g" \
        -e "s|CONFIG|${this}/etc/frontend.json|g" \
        -e "s|USER|${user}|g" \
        -e "s|PRE|${this}/bin/port.sh addChain|g"  daemon/v2frontend.service > /tmp/v2frontend.service

    runAsRoot "mv /tmp/v2frontend.service /etc/systemd/system/v2frontend.service"
    runAsRoot "systemctl enable v2frontend"
    echo "systemd service v2frontend has been installed."

    sed -e "s|V2RAY|${this}/Linux/v2ray|g" \
        -e "s|USER|${user}|g" \
        -e "s|CONFIG|${this}/etc/backend.json|g" \
        -e "s|START_PRE|${this}/bin/v2relay.sh start_pre|g" \
        -e "s|START_POST|${this}/bin/v2relay.sh start_post|g" \
        -e "s|STOP_POST|${this}/bin/v2relay.sh stop_post|g"  daemon/v2backend.service > /tmp/v2backend.service
    runAsRoot "mv /tmp/v2backend.service /etc/systemd/system/v2backend.service"
    runAsRoot "systemctl enable v2backend"
    echo "systemd service v2backend has been installed."

    echo "Note: in crontab please enable no password to run sudo if you are not root"
    echo "add ${this}/bin to PATH manually"
}

_build(){
    cd /tmp
    if [ ! -d fetchSubscription ];then
        git clone https://gitee.com/sunliang711/fetchSubscription || { echo "clone fetchSubscription error "; exit 1; }
    else
        echo "use /tmp/fetchSubscription cache"
    fi
    cd fetchSubscription && git pull && bash ./build.sh build && cp fetch  ${this}/bin && cp v2ray.tmpl ${this}/etc
    cd ${this}

    cd ./fastestPort
    ./build.sh build
    cd ${this}
}

uninstall(){
    ./bin/v2relay.sh stop
    rm ./bin/fetch 2>/dev/null
    rm ./bin/v2ray.tmpl 2>/dev/null
    runAsRoot "rm /etc/systemd/system/v2frontend.service"
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
