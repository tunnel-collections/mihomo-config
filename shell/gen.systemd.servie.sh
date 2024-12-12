#!/bin/bash

# 获取当前脚本对应目录，放在变量 CRASHDIR 中
CRASHDIR=$(cd "$(dirname "$0")"; pwd)
# BIN_NAME="mihomo-linux-arm64-v1.18.0"

# BIN_NAME="mihomo-linux-amd64-compatible"
BIN_NAME="mihomo-linux-amd64-compatible-v1.18.5"


cat > /etc/systemd/system/clash.service << EOF
[Unit]
Description=Clash Meta Service
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$CRASHDIR
ExecStart=$CRASHDIR/$BIN_NAME -d $CRASHDIR -f $CRASHDIR/m.yaml
User=shellclash
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF


cat > /etc/systemd/system/iptables-persistent.service << \EOF
[Unit]
Description=Iptables Persistent
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore -v -n /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
