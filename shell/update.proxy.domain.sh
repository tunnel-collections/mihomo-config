#/bin/bash

# 将代理 域名放到 mosdns 目录下，这些域名走直连
cat m.yaml | grep "节点绕过"|grep -Eo '([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' > mosdns.proxies.txt