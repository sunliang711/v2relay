#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
thisDir="$(cd $(dirname $rpath) && pwd)"
cd "$thisDir"

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
declare -A ports=([8000]=nicoleFriend [8001]=nicole [8002]=chuan [8003]=no [8004]=xiang [8005]=me [8006]=wei [8020]=socks5 [8021]=21 [8022]=vmess)

editor=vi
if command -v vim >/dev/null 2>&1;then
    editor=vim
fi
if command -v nvim >/dev/null 2>&1;then
    editor=nvim
fi

dest=${thisDir}/../net-traffic

function init(){
    if command -v iptables-legacy >/dev/null 2>&1;then
        cmdIptbl=iptables-legacy
    elif command -v iptables >/dev/null 2>&1;then
        cmdIptbl=iptables
    else
        echo "iptables command not found!"
        exit 1
    fi
    cmdIptbl=iptables
}

list(){
    init
    for port in "${!ports[@]}";do
        echo "port: $port comment=${ports[$port]}"
    done

}

#add ports to iptables chain
addChain(){
    init
    for port in "${!ports[@]}";do
        if ! sudo ${cmdIptbl} -L OUTPUT -n --line-numbers | grep -qP "spt:$port\b";then
            echo "add port: $port to OUTPUT"
            sudo ${cmdIptbl} -A OUTPUT -p tcp --sport $port
        fi
        if ! sudo ${cmdIptbl} -L INPUT -n --line-numbers | grep -qP "dpt:$port\b";then
            echo "add port: $port to INPUT"
            sudo ${cmdIptbl} -A INPUT -p tcp --dport $port
        fi
    done
}

#clear ports from iptables chain
clearChain(){
    init
    for port in ${!ports[@]};do
        echo "clear port: $port..."
        sudo ${cmdIptbl} -L INPUT -n --line-numbers | grep -P "dpt:$port\b" | awk '{print $1}' | xargs -L 1 sudo ${cmdIptbl} -D INPUT
        sudo ${cmdIptbl} -L OUTPUT -n --line-numbers | grep -P "spt:$port\b" | awk '{print $1}' | xargs -L 1 sudo ${cmdIptbl} -D OUTPUT
    done
}

#zero counter in iptables
zero(){
    init
    for port in ${!ports[@]};do
        echo "zero port: $port..."
        sudo ${cmdIptbl} -L INPUT -n --line-numbers | grep -P "dpt:$port\b" | awk '{print $1}' | xargs -L 1 sudo ${cmdIptbl} -L -Z INPUT
        sudo ${cmdIptbl} -L OUTPUT -n --line-numbers | grep -P "spt:$port\b" | awk '{print $1}' | xargs -L 1 sudo ${cmdIptbl} -L -Z OUTPUT
    done
}

function show(){
    _show
}

function _show(){
    init
    #-x -L INPUT|OUTPUT 输出的流量以字节为单位
    declare -a chains=(INPUT OUTPUT)
    inByte=${1}

    for chain in "${chains[@]}";do
        sudo "${cmdIptbl}" -L $chain -n -v | head -1
        printf "%-10s%-10s%-18s%-18s%-18s\n" "protocol" "port" "comment" "bytes" "packets"
        local output="$(sudo "${cmdIptbl}" -L ${chain} -nv ${inByte})"
        for port in "${!ports[@]}";do
             # echo "$output"| grep -E "(dpt|spt):${port}\b" | awk -v comment=${ports[$port]} '{printf "%-10s%-10s%-18s%-18s%-18s\n",$3,$10,comment,$2,$1}' | perl -ple "s|(?<=\d)(?=(\d{3})+\b)|,|g"
             IFS='|'
             # protocol port bytes pkts
             local comment=${ports[$port]}
             read pro pt bs pks <<< $(echo "$output"| grep -E "(dpt|spt):${port}\b" | awk '{printf "%s|%s|%s|%s",$3,$10,$2,$1}')
             # bs=$(printf "%'d" $bs)
             # pks=$(printf "%'d" $pks)
             # add comma: 1234567 -> 1,234,567
             bs=$(echo $bs | perl -ple "s|(?<=\d)(?=(\d\d\d)+\D*$)|,|g" )
             pks=$(echo $pks | perl -ple "s|(?<=\d)(?=(\d\d\d)+\D*$)|,|g" )
             printf "%-10s%-10s%-18s%-18s%-18s\n" "$pro" "$pt" "$comment" "$bs" "$pks"
        done
    done
}

function _monitor(){
    echo "Press <C-c> to quit."
    date +%FT%T
    echo
    _show $1
}

monitor(){
    echo "add -x to show traffic in byte"
    watch -d -n 1 $0 _monitor $1
}

saveDay(){
    init
    local filename=year-$(date +%Y)
    if [ ! -d $dest ];then
        mkdir $dest
    fi
    (date +%FT%T;show) >> $dest/$filename
    zero
}

saveHour(){
    init
    local filename=month-$(date +%Y%m)
    if [ ! -d $dest ];then
        mkdir $dest
    fi
    echo "saveHour to $dest/$filename"
    (date +%FT%T;show) >> $dest/$filename
}

em(){
    $editor ${BASH_SOURCE}
}

day(){
    local filename=year-$(date +%Y)
    $editor $dest/$filename
}

hour(){
    local filename=month-$(date +%Y%m)
    $editor $dest/$filename
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
