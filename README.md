>
启动v2ray进程，并开启http 代理端口、socks5代理端口、ss服务端端口(在inbounds项)；
出口方向(outbound)指向远端服务器；

## install.sh
    install.sh 安装脚本，把本服务安装到systemd系统上，使用的配置文件位于v2ray-linux/v2ray.json


## bin/port.sh
    port.sh 用于管理inbounds里面涉及到的端口的流量统计；

## bin/v2relay.sh
    管理服务启停、配置的脚本；

## lede_install.sh
    在koolshare lede上的安装脚本
