#!/bin/sh
dest=/usr/local/etc/rc.d

cd $dest/v2ray-linux

./v2ray -c v2ray.json
