#!/bin/bash

# 获取当前脚本对应目录，放在变量 CRASHDIR 中
CRASHDIR=$(cd "$(dirname "$0")"; pwd)
# BIN_NAME="mihomo-linux-arm64-v1.18.0"

BIN_NAME="mihomo-linux-amd64-compatible"

cat > /etc/init.d/clash << EOF
#!/bin/sh /etc/rc.common
#
# Copyright (C) 2020-2022, IrineSistiana
#
# This file is part of clash.
#
# clash is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# clash is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

START=99
USE_PROCD=1

#####  ONLY CHANGE THIS BLOCK  ######

CRASHDIR=$CRASHDIR
PROG=\$CRASHDIR/$BIN_NAME
CONF=\$CRASHDIR/m.yaml

#####  ONLY CHANGE THIS BLOCK  ######

start_service() {
	echo "try to start clash"
	#检测必须文件
	bash "$CRASHDIR/init.sh" bfstart
	if [ "\$?" = "0" ];then
		#使用procd创建clash后台进程
		procd_open_instance
		procd_set_param user shellclash
		procd_set_param respawn "\${respawn_threshold:-3600}" "\${respawn_timeout:-5}" "\${respawn_retry:-5}"
		procd_set_param stderr 1
		procd_set_param stdout 1
		procd_set_param command \$PROG -d \$CRASHDIR -f \$CONF
		procd_close_instance
		#其他设置
		bash -x "$CRASHDIR/init.sh" afstart
	fi
}

stop_service() {
	echo "stop clash"
	killall mihomo
	if [ "\$?" = "0" ]; then
		echo "stop clash success"
	else
		echo "stop clash failed"
	fi
	bash $CRASHDIR/init.sh afstop
}

reload_service() {
	echo "reload clash"
	stop
	sleep 2s
	start
	ct=\`ps -ef |grep mihomo |grep -v grep |wc -l\`
	if [ "\$ct" -ge 1 ]; then
		echo "clash restart success"
	else
		echo "clash restart failed \$ct"
	fi
}
EOF

chmod a+x /etc/init.d/clash

cat > init.sh << EOF
#!/bin/bash

bfstart(){
	modprobe iptable_nat
	modprobe xt_REDIRECT

	# 创建用户
	grep -qw shellclash /etc/passwd || echo "shellclash:x:0:7890:::" >> /etc/passwd

	# 判断是否存在 iptables 规则
	iptables -t nat -nL clash >/dev/null 2>&1
	if [ "\$?" != "0" ];then
		bash -x $CRASHDIR/clash.fake-ip.iptables.sh
	fi
}

afstart(){
	# 获取 ipset_cn_ip
	$CRASHDIR/tools/getoip2ipset -ipset ipset_cn_ip -timeout 0
}

afstop(){
	echo "fstop"
	# 判断是否存在 iptables 规则，如果存在，则删除
	iptables -t nat -nL clash >/dev/null 2>&1
	if [ "\$?" != "0" ];then
		bash "$CRASHDIR/clash.fake-ip.iptables.reset.sh"
	fi
}
EOF
chmod a+x init.sh
