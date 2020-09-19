#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
thisDir="$(cd $(dirname $rpath) && pwd)"
cd "$thisDir"

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
    _build
    cat msg
    bash download.sh || { echo "Download v2ray failed!"; exit 1; }
    sed -e "s|V2RAY|${thisDir}/Linux/v2ray|g" \
        -e "s|CONFIG|${thisDir}/etc/config.json|g" \
        -e "s|PRE|${thisDir}/bin/port.sh addChain|g"  v2relay.service > /tmp/v2relay.service

    runAsRoot "mv /tmp/v2relay.service /etc/systemd/system/v2relay.service"
    echo "systemd service v2relay has been installed."

    sed -e "s|V2RAY|${thisDir}/Linux/v2ray|g" \
        -e "s|CONFIG|${thisDir}/etc/backend.json|g"  v2backend.service > /tmp/v2backend.service
    runAsRoot "mv /tmp/v2backend.service /etc/systemd/system/v2backend.service"
    echo "systemd service v2backend has been installed."

    echo "add ${thisDir}/bin to PATH manually"
}

_build(){
    cd /tmp
    if [ ! -d fetchSubscription ];then
        git clone https://gitee.com/sunliang711/fetchSubscription || { echo "clone fetchSubscription error "; exit 1; }
    fi
    cd fetchSubscription && bash ./build.sh build && cp fetch v2ray.tmpl ${thisDir}/bin
    cd ${thisDir}
}

uninstall(){
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
