#/bin/bash

# 将代理 ip 放到 ipset 中，防止循环代理
cat ../data/m.yaml |grep "节点绕过" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' |xargs -I {} bash -c  "ipset add ipset_proxy_ip {}"