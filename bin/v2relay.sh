#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
this="$(cd $(dirname $rpath) && pwd)"
cd "$this"

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 5)
bold=$(tput bold)
reset=$(tput sgr0)
function _runAsRoot(){
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
editor=vi
if command -v vim >/dev/null 2>&1;then
    editor=vim
fi
if command -v nvim >/dev/null 2>&1;then
    editor=nvim
fi
###############################################################################
# write your code below (just define function[s])
# function is hidden when begin with '_'
###############################################################################
# TODO
# redirect virtualPort to bestPort
firewallCMD=
if command -v iptables >/dev/null 2>&1;then
    firewallCMD=iptables
fi
if command -v iptables-legacy >/dev/null 2>&1;then
    firewallCMD="iptables-legacy"
fi
serviceName=v2relay
backendName=v2backend
rootid=0
_root(){
    if [ $EUID -ne $rootid ];then
        echo "Need root privilege"
        exit 1
    fi
}

start(){
    _checkVirtualPort
    _runAsRoot "systemctl start $serviceName"
    _runAsRoot "systemctl start ${backendName}"
    selectBest
}

stop(){
    _runAsRoot "systemctl stop $serviceName"
    _runAsRoot "systemctl stop ${backendName}"
    _clearRule
}

restart(){
    stop
    start
}

status(){
    _runAsRoot "systemctl status $serviceName"
}

backendConfig=backend.json
subURLFile=${this}/../etc/sub.txt
fetchSub(){
    cd ${this}
    ./fetch -o ${this}/../etc/${backendConfig} -u $(cat ${subURLFile})
}

_need(){
    if ! command -v $1 >/dev/null 2>&1;then
        echo "need $1"
        exit 1
    fi
}

_virtualPort(){
    cd ${this}
    local outPort=$(perl -lne "print if /BEGIN virtual port/../END virtual port/" ../etc/config.json | grep "\"port\"" | grep -o '[0-9][0-9]*')
    echo "${outPort}"

}

selectBest(){
    backPorts=$(_backendPorts)
    if [ -z "${backPorts}" ];then
        echo "Error: cannot find any backend port"
        exit 1
    fi

    time=/usr/bin/time
    result=times
    echo -n >${result}
    for port in ${backPorts//,/ };do
        echo "test port: $port..."
        echo -n "${port} " >> ${result}
        ${time} --quiet -f "%e" curl -x socks5://localhost:$port -s -o /tmp/bestPortAnswer ifconfig.me 2>> ${result}
    done

    local bestPort=$(sort -n -k 2 ${result} | head -1 | awk '{print $1}')
    if [ -z "${bestPort}" ];then
        echo "find best port error"
        exit 1
    fi
    echo "best port: ${bestPort}"

    local virtualPort=$(_virtualPort)


    tbl=redirtable

    # delete reference
    echo "delete reference"
    _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L OUTPUT | grep ${tbl} | grep -o '^[0-9][0-9]*' | xargs -t -n 1 ${firewallCMD} -t nat -D OUTPUT"
    _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L PREROUTING | grep ${tbl} | grep -o '^[0-9][0-9]*' | xargs -t -n 1 ${firewallCMD} -t nat -D PREROUTING"

    # echo "after reference"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"

    #flush
    echo "flush chain"
    _runAsRoot "${firewallCMD} -t nat -F ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -X ${tbl}"

    # echo "after flush chain"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"

    #new
    echo "new chain"
    _runAsRoot "${firewallCMD} -t nat -N ${tbl}"

    # echo "after new chain"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"

    echo "add rule to chain: bestPort: $bestPort"
    _runAsRoot "${firewallCMD} -t nat -A ${tbl} -p tcp --dport ${virtualPort} -j REDIRECT --to-ports ${bestPort}"
    # echo "after add rule to chain"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"

    #reference
    echo "reference"
    _runAsRoot "${firewallCMD} -t nat -A OUTPUT -p tcp --dport ${virtualPort} -j ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -A PREROUTING -p tcp --dport ${virtualPort} -j ${tbl}"

    # echo "after reference"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"
}

_clearRule(){
    tbl=redirtable

    # delete reference
    echo "delete reference"
    _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L OUTPUT | grep ${tbl} | grep -o '^[0-9][0-9]*' | xargs -t -n 1 ${firewallCMD} -t nat -D OUTPUT"
    _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L PREROUTING | grep ${tbl} | grep -o '^[0-9][0-9]*' | xargs -t -n 1 ${firewallCMD} -t nat -D PREROUTING"

    #flush
    echo "flush chain"
    _runAsRoot "${firewallCMD} -t nat -F ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -X ${tbl}"
}

_checkVirtualPort(){
    cd ${this}
    _need nc
    # find outPort
    local outPort=$(_virtualPort)
    echo "virtual outPort: $outPort"
    if [ -z "$outPort" ];then
        echo "Error: cannot find outPort!"
        exit 1
    fi
    if nc -z localhost ${outPort} >/dev/null 2>&1;then
        echo "${outPort} is in use,please use another port"
        exit 1
    fi
}

_backendPorts(){
    perl -lne 'print if /\/\/InPorts:/' ../etc/backend.json | awk -F: '{print $2}'
}

config(){
    configFile=${this}/../etc/config.json
    mtime0=$(stat $configFile | grep Modify)
    $editor ${configFile}
    mtime1=$(stat $configFile | grep Modify)

    if [[ ${mtime0} != ${mtime1} ]];then
        echo "config file changed,restart service..."
        restart
    fi
}

log(){
    _runAsRoot "tail -f /tmp/v2relay.log"
}

logb(){
    _runAsRoot "tail -f /tmp/v2ray-backend.log"
}

em(){
    $editor ${BASH_SOURCE}
}

###############################################################################
# write your code above
###############################################################################
function _help(){
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    # perl -lne 'print "\t$1" if /^\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE})
    # perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | grep -v '^\t_'
    perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | perl -lne "print if /^\t[^_]/"
}

function _loadENV(){
    if [ -z "$INIT_HTTP_PROXY" ];then
        echo "INIT_HTTP_PROXY is empty"
        echo -n "Enter http proxy: (if you need) "
        read INIT_HTTP_PROXY
    fi
    if [ -n "$INIT_HTTP_PROXY" ];then
        echo "set http proxy to $INIT_HTTP_PROXY"
        export http_proxy=$INIT_HTTP_PROXY
        export https_proxy=$INIT_HTTP_PROXY
        export HTTP_PROXY=$INIT_HTTP_PROXY
        export HTTPS_PROXY=$INIT_HTTP_PROXY
        git config --global http.proxy $INIT_HTTP_PROXY
        git config --global https.proxy $INIT_HTTP_PROXY
    else
        echo "No use http proxy"
    fi
}

function _unloadENV(){
    if [ -n "$https_proxy" ];then
        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        git config --global --unset-all http.proxy
        git config --global --unset-all https.proxy
    fi
}


case "$1" in
     ""|-h|--help|help)
        _help
        ;;
    *)
        "$@"
esac
