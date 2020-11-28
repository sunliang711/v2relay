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

export TERM=xterm-256color
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
serviceName=v2frontend
backendName=v2backend
rootid=0
_root(){
    if [ $EUID -ne $rootid ];then
        echo "Need root privilege"
        exit 1
    fi
}

start(){
    # _checkVirtualPort
    _runAsRoot "systemctl start $serviceName &"
    _runAsRoot "systemctl start ${backendName} &"

    _runAsRoot "journalctl -u ${backendName} -f"
    # selectBest
    # _addCron
}

start_pre(){
    _checkVirtualPort
}

start_post(){
    selectBest2
    _addCron
}


stop(){
    _runAsRoot "systemctl stop $serviceName"
    _runAsRoot "systemctl stop ${backendName}"
    # _clearRule
    # _delCron
}

stop_post(){
    _clearRule
    _delCron
}

restart(){
    stop
    start
}

status(){
    _runAsRoot "systemctl status $serviceName"
}

backendConfig=${this}/../etc/backend.json
newBackendConfig=/tmp/newbackend.json
subURLFile=${this}/../etc/sub.txt
backends=${this}/../etc/backends
filterList="w:VIP2|b:游戏"
# filterList="b:游戏"
fetchSub(){
    cd ${this}
    local subURL="$(cat ${subURLFile})"
    echo "fetch subscription: to file ${backendConfig} with url: ${subURL} filter list: ${filterList} ..."
    ./fetch -o ${newBackendConfig} -t ${this}/../etc/v2ray.tmpl -p 18000 -u ${subURL} --filter ${filterList} -l info

    if [ $? -eq 0 ];then
        if [ ! -d ${backends} ];then
            mkdir -p ${backends}
        fi
        if [ -e ${backendConfig} ];then
            echo "Backup old config file ${backendConfig} to ${backends}/"
            mv ${backendConfig} ${backends}/backend-$(date +%FT%T).json
        fi
        echo "Move new config file: ${newBackendConfig} to ${backendConfig}"
        mv ${newBackendConfig} ${backendConfig}
    fi
}

editSub(){
    cd ${this}
    ${editor} ${subURLFile}
}

_need(){
    if ! command -v $1 >/dev/null 2>&1;then
        echo "need $1"
        exit 1
    fi
}

_virtualPort(){
    cd ${this}
    local outPort=$(perl -lne "print if /BEGIN virtual port/../END virtual port/" ../etc/frontend.json | grep "\"port\"" | grep -o '[0-9][0-9]*')
    echo "${outPort}"

}

selectBest(){
    echo "Begin select best..."
    backPorts=$(_backendPorts)
    if [ -z "${backPorts}" ];then
        echo "Error: cannot find any backend port"
        exit 1
    fi

    time=/usr/bin/time
    local result=/tmp/selectBest.results
    local tmpFile=/tmp/selectBest.result
    local elapsed=/tmp/seleceBest.elapsed

    local separator='`'
    # clear ${result} file
    echo -n >${result}
    while read -r portPs;do
        local port=${portPs%:*}
        local ps=${portPs#*:}
        echo -n "$(date +%FT%T) test port: $port ps: $ps ... "
        echo -n "${port}${separator}${ps}${separator}" > ${tmpFile}
        ${time} --quiet -f "%e" curl -m 10 -x socks5://localhost:$port -s -o /tmp/bestPortAnswer ifconfig.me 2> ${elapsed}
        if [ $? -ne 0 ];then
            echo "[Error]"
            continue
        else
            cat ${elapsed} >> ${tmpFile}
            echo -n "[OK] elapsed: "
            cat ${elapsed}
        fi

        cat ${tmpFile} >> ${result}
    done <<< ${backPorts}

    echo "[Test result]:"
    cat ${result}

    local bestLine=$(sort -n -t ${separator} -k 3 ${result} | head -1)
    echo "best node: ${bestLine}"
    local bestPort=$(echo ${bestLine} | awk -F${separator} '{print $1}')
    if [ -z "${bestPort}" ];then
        echo "find best port error"
        echo "suggest: run fetchSub?"
        exit 1
    fi
    echo "best port: ${bestPort}"

    # /bin/rm -rf ${result}

    local virtualPort=$(_virtualPort)


    _clearRule
    _addRule ${virtualPort} ${bestPort}

}

selectBest2(){
    local portPsFileName=$(perl -lne 'print $1 if /portFile="(.+)"/' ../fastestPort/config.toml)
    echo "portPsFileName: ${portPsFileName}"
    _backendPorts > "${portPsFileName}"

    local result=$(perl -lne 'print $1 if /resultFile="(.+)"/' ../fastestPort/config.toml)
    echo "resultFile: ${result}"
    ../fastestPort/fastestPort -c ../fastestPort/config.toml

    echo "[Test result]:"
    cat ${result}

    local separator='`'
    local bestLine=$(sort -n -t ${separator} -k 2 ${result} | head -1)
    echo "best node: ${bestLine}"
    local bestPort=$(echo ${bestLine} | awk -F${separator} '{print $1}')
    if [ -z "${bestPort}" ];then
        echo "find best port error"
        echo "suggest: run fetchSub?"
        exit 1
    fi
    echo "best port: ${bestPort}"

    # /bin/rm -rf ${result}

    local virtualPort=$(_virtualPort)


    _clearRule
    _addRule ${virtualPort} ${bestPort}
}

check(){
    echo -n "$(date +%FT%T) check..."
    local outPort=$(_virtualPort)
    if curl -s -x socks5://localhost:${outPort} --retry 2 ifconfig.me >/dev/null 2>&1;then
        echo "OK"
    else
        echo
        selectBest2
    fi
}

beginCron="#begin v2relay cron"
endCron="#end v2relay cron"

_addCron(){
    local tmpCron=/tmp/cron.tmp$(date +%FT%T)
    if crontab -l 2>/dev/null | grep -q "${beginCron}";then
        echo "Already exist,quit."
        return 0
    fi
    cat<<-EOF>${tmpCron}
	${beginCron}
	# NOTE!! saveHour saveDay need run iptables with sudo,
	# so make sure you can run iptables with sudo no passwd
	# or you are root
	0 * * * * ${this}/port.sh saveHour
	59 23 * * * ${this}/port.sh saveDay
	# */20 * * * * ${this}/v2relay.sh selectBest2 >>/tmp/selectBest2.log 2>&1
	# 
	# Peek Hour: 9-23,0-2 
	5 9-23,0-2 * * * ${this}/v2relay.sh selectBest2 >>/tmp/selectBest2.log 2>&1
	*/3 9-23,0-2 * * * ${this}/v2relay.sh check >>/tmp/selectBest2.log 2>&1

	# Not Peek Hour: 3-8
	5 3-8 * * * ${this}/v2relay.sh selectBest2 >>/tmp/selectBest2.log 2>&1
	0,30 3-8 * * * ${this}/v2relay.sh check >>/tmp/selectBest2.log 2>&1

	${endCron}
	EOF

    (crontab -l 2>/dev/null ;cat ${tmpCron}) | crontab -
}

_delCron(){
    (crontab -l 2>/dev/null | sed -e "/${beginCron}/,/${endCron}/d") | crontab -
}

_tabEcho(){
    echo -e "\t$*"
}

tbl=redirchain
_clearRule(){
    echo "Clear rule..."
    # delete reference
    _tabEcho "Delete reference"
    #如果有多条的话，要从index大的开始删除，否则会报index越界错误,所以要sort -r倒序；因为删除小的后，大的index会变小
    _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L OUTPUT | grep ${tbl} | grep -o '^[0-9][0-9]*' | sort -r | xargs -n 1 ${firewallCMD} -t nat -D OUTPUT"
    _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L PREROUTING | grep ${tbl} | grep -o '^[0-9][0-9]*' | sort -r | xargs -n 1 ${firewallCMD} -t nat -D PREROUTING"

    #flush
    _tabEcho "Flush chain: ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -F ${tbl}"

    #delete
    _tabEcho "Delete chain: ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -X ${tbl}"
}

_addRule(){
    echo "Add rule..."
    local srcPort=${1:?'missing src port'}
    local destPort=${2:?'missing dest port'}
    # new
    _tabEcho "New chain: ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -N ${tbl}"

    # echo "after new chain"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"

    _tabEcho "Add rule to chain: ${tbl} with destPort: $destPort"
    _runAsRoot "${firewallCMD} -t nat -A ${tbl} -p tcp --dport ${srcPort} -j REDIRECT --to-ports ${destPort}"
    # echo "after add rule to chain"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"

    # reference
    _tabEcho "Reference chain: ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -A OUTPUT -p tcp --dport ${srcPort} -j ${tbl}"
    _runAsRoot "${firewallCMD} -t nat -A PREROUTING -p tcp --dport ${srcPort} -j ${tbl}"

    # echo "after reference"
    # _runAsRoot "${firewallCMD} -t nat -n --line-numbers -L"

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
    # perl -lne 'print if /\/\/InPorts:/' ../etc/backend.json | awk -F: '{print $2}'
    perl -lne 'print $1 if /"BEGIN port":"([^"]+)"/' ../etc/backend.json
}

config(){
    configFile=${this}/../etc/frontend.json
    mtime0=$(stat $configFile | grep Modify)
    $editor ${configFile}
    mtime1=$(stat $configFile | grep Modify)

    if [[ ${mtime0} != ${mtime1} ]];then
        echo "config file changed,restart service..."
        restart
    fi
}

log(){
    _runAsRoot "tail -f /tmp/v2ray-frontend.log"
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
