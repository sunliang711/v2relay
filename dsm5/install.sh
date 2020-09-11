#!/bin/sh
dest=/usr/local/etc/rc.d

cp -r ../v2ray-linux $dest
cp -r startv2rayproxy.sh $dest
chmod +x $dest/startv2rayproxy.sh
