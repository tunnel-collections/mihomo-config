#!/bin/bash

# 获取当前脚本对应目录，放在变量 CRASHDIR 中
CRASHDIR=$(cd "$(dirname "$0")"; pwd)
# 获取上级目录
PARENT_DIR=$(dirname $CRASHDIR)
source $CRASHDIR/config.cfg

[ -z "$DNS_PORT" ] && DNS_PORT=1053
[ -z "$REDIR_PORT" ] && REDIR_PORT=1234
[ -z "$MIXED_PORT" ] && MIXED_PORT=7788
[ -z "$API_PORT" ] && API_PORT=1111
[ -z "$SECRET" ] && SECRET=1008611
[ -z "$FAKE_IP_RANGE" ] && FAKE_IP_RANGE=28.0.0.1/8
[ -z "$ENABLE_CUSTOM_DNS" ] && ENABLE_CUSTOM_DNS=1
[ -z "$CUSTOM_DNS" ] && CUSTOM_DNS=127.0.0.1:5333
[ -z "$ENABLE_DIRECT_PROXY" ] && ENABLE_DIRECT_PROXY=1
[ -z "$PROXY_MODE" ] && PROXY_MODE="fake-ip"
#[ -z "$PROXY_MODE" ] && PROXY_MODE="redir-host"


CONFIG_PATH=$CRASHDIR/m.yaml

HEALTH_CHECK_URL="http://www.gstatic.com/generate_204"
# HEALTH_CHECK_URL="https://cp.cloudflare.com/generate_204"

# config provider
#####################################################################################################################


PROVIDER_NAME_LIST=""
for key in "${!PROVIDER_LIST[@]}"; do
  value=${PROVIDER_LIST[$key]}
  if [[ ! ${value} =~ ^# ]]; then
    echo "provider => $key, url => $value "
    PROVIDER_NAME_LIST+=$(echo -n "    - P-${key}")
    PROVIDER_NAME_LIST+=$'\n' # 添加换行符
  fi
done

# echo "$PROVIDER_NAME_LIST"

cat > ${CONFIG_PATH} << EOF
###########################################################################################################################
#                                             订阅内容，不要公开
###########################################################################################################################
# http://www.gstatic.com/generate_204
# https://cp.cloudflare.com/generate_204
p: &p {type: http, interval: 3600, health-check: {enable: true, url: $HEALTH_CHECK_URL, interval: 300}}


SELECT_FILTER: &SELECT_FILTER
  type: select
  use:
$PROVIDER_NAME_LIST

ULT_FILTER: &ULT_FILTER
  type: url-test
  lazy: true
  url: "$HEALTH_CHECK_URL"
  interval: 300
  use:
$PROVIDER_NAME_LIST
FB_FILTER: &FB_FILTER
  type: fallback
  url: "$HEALTH_CHECK_URL"
  interval: 300
  use:
$PROVIDER_NAME_LIST
# --------------------------------------------------------------------
EOF

# 定义一个独立的选择器，按 provider 显示，这样代理的地方可以按单独的 provider 选择
for key in "${!PROVIDER_LIST[@]}"; do
  value=${PROVIDER_LIST[$key]}
  if [[ ! ${value} =~ ^# ]]; then
    echo "${key}_ULT_FILTER: &${key}_ULT_FILTER" >> ${CONFIG_PATH}
    echo "  type: url-test" >> ${CONFIG_PATH}
    echo "  lazy: true" >> ${CONFIG_PATH}
    echo "  url: \"$HEALTH_CHECK_URL\"" >> ${CONFIG_PATH}
    echo '  interval: 300' >> ${CONFIG_PATH}
    echo '  use:' >> ${CONFIG_PATH}
    echo "    - P-${key}" >> ${CONFIG_PATH}
    echo "" >> ${CONFIG_PATH}
  fi
done


cat >> ${CONFIG_PATH} << \EOF

proxy-providers:
EOF

for key in "${!PROVIDER_LIST[@]}"; do
  value=${PROVIDER_LIST[$key]}
  if [[ ! ${value} =~ ^# ]]; then
    echo "  P-${key}:" >> ${CONFIG_PATH}
    echo "    url: '${value}'" >> ${CONFIG_PATH}
    echo "    path: './proxies/${key}.yaml'" >> ${CONFIG_PATH}
    echo "    <<: *p" >> ${CONFIG_PATH}
  fi
done


cat >> ${CONFIG_PATH} << \EOF

###########################################################################################################################
#                                订阅内容到此结束，以上内容不要公开
###########################################################################################################################

EOF


# config base
#####################################################################################################################
cat >> ${CONFIG_PATH} << EOF
mixed-port: $MIXED_PORT
redir-port: $REDIR_PORT
tproxy-port: 7894
allow-lan: true
mode: rule
log-level: info

# web ui 访问地址
external-controller: '0.0.0.0:$API_PORT'
#external-ui: clash-dashboard
external-ui: yacd
secret: '$SECRET'
ipv6: false


# use geo if true else mmdb
geodata-mode: true
geo-auto-update: true
geo-update-interval: 24
geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"


find-process-mode: off
global-client-fingerprint: chrome

profile:
  store-selected: true
  store-fake-ip: false
EOF

cat >> ${CONFIG_PATH} << \EOF

# 嗅探域名 可选配置
sniffer:
  enable: false
  ## 对所有未获取到域名的流量进行强制嗅探
  parse-pure-ip: true
  # 是否使用嗅探结果作为实际访问，默认 true
  override-destination: true
  sniff: # TLS 和 QUIC 默认如果不配置 ports 默认嗅探 443
    QUIC:
     ports: [ 443 ]
    TLS:
     ports: [443, 8443]

    # 默认嗅探 80
    HTTP: # 需要嗅探的端口
      ports: [80, 8080-8880]
      override-destination: true
  force-domain:
    - +.v2ex.com
  skip-domain:
    - Mijia Cloud
  sniffing:
    - tls
    - http

  # 仅对白名单中的端口进行嗅探，默认为 443，80
  # 已废弃，若 sniffer.sniff 配置则此项无效
  port-whitelist:
    - "80"
    - "443"
    - 8000-9000

EOF

# config dns
#####################################################################################################################
cat >> ${CONFIG_PATH} << EOF
dns:
  enable: true
  cache-algorithm: arc
  prefer-h3: true
  listen: :$DNS_PORT
  ipv6: false
  enhanced-mode: $PROXY_MODE
  fake-ip-range: $FAKE_IP_RANGE
  fake-ip-filter:
EOF

cat $CRASHDIR/rules/fake_ip_filter.list 2>/dev/null | grep '\.' | sed "s/^/    - '/" | sed "s/$/'/" >> ${CONFIG_PATH}

cat >> ${CONFIG_PATH} << EOF
  # 用于解析 nameserver，fallback 以及其他DNS服务器配置的，DNS 服务域名
  # 只能使用纯 IP 地址，可使用加密 DNS
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29

  # 这部分为主要 DNS 配置，影响所有直连，确保使用对大陆解析精准的 DNS
  nameserver:
    - $CUSTOM_DNS
    #- https://doh.pub/dns-query#h3=true
    #- https://dns.alidns.com/dns-query#h3=true

  fallback:
    - $CUSTOM_DNS
    #- 'https://dns.cloudflare.com/dns-query#P-Proxy&h3=true'
    #- 'tls://8.8.8.8#P-Proxy'

  # 配置 fallback 使用条件
  fallback-filter:
    geoip: true # 配置是否使用 geoip
    geoip-code: CN # 当 nameserver 域名的 IP 查询 geoip 库为 CN 时，不使用 fallback 中的 DNS 查询结果
    # 配置强制 fallback，优先于 IP 判断，具体分类自行查看 geosite 库
    geosite:
      - gfw
    # 返回结果在 240.0.0.0/4 范围代表被污染了，使用 fallback 的 dns server 解析
    ipcidr:
      - 240.0.0.0/4
    # 强制使用 fallback 解析的域名
    domain:
      - '+.google.com'
      - '+.facebook.com'
      - '+.youtube.com'
      - '+.github.com'
      - '+.cloudflare.com'

EOF

# config proxy
#####################################################################################################################
cat >> ${CONFIG_PATH} << \EOF
proxy-groups:
EOF

for key in "${!PROVIDER_LIST[@]}"; do
  value=${PROVIDER_LIST[$key]}
  if [[ ! ${value} =~ ^# ]]; then
    echo "  - { name: P-TW-ULT-${key}, <<: *${key}_ULT_FILTER, filter: \"(?i)台湾|台北|tw|taiwan\" }" >> ${CONFIG_PATH}
    echo "  - { name: P-US-ULT-${key}, <<: *${key}_ULT_FILTER, filter: \"(?i)美国|广美|us|usa|united states\" }" >> ${CONFIG_PATH}
    echo "  - { name: P-SGP-ULT-${key}, <<: *${key}_ULT_FILTER, filter: \"(?i)新加坡|狮城|广新|sg|singapore\" }" >> ${CONFIG_PATH}
  fi
done


PROVIDER_PROXY_NAME_LIST=""
for key in "${!PROVIDER_LIST[@]}"; do
  value=${PROVIDER_LIST[$key]}
  if [[ ! ${value} =~ ^# ]]; then
    PROVIDER_PROXY_NAME_LIST+=$(echo -n " ,P-TW-ULT-${key}, P-US-ULT-${key}, P-SGP-ULT-${key}")
  fi
done

# echo "$PROVIDER_PROXY_NAME_LIST"

cat >> ${CONFIG_PATH} << EOF
  # 台湾
  - { name: P-TW, <<: *SELECT_FILTER, filter: "(?i)台湾|台北|tw|taiwan" }
  - { name: P-TW-FB, <<: *FB_FILTER, filter: "(?i)台湾|台北|tw|taiwan" }
  - { name: P-TW-ULT, <<: *ULT_FILTER, filter: "(?i)台湾|台北|tw|taiwan" }

  # 新加坡
  - { name: P-SGP, <<: *SELECT_FILTER, filter: "(?i)新加坡|狮城|广新|sg|singapore" }
  - { name: P-SGP-FB, <<: *FB_FILTER, filter: "(?i)新加坡|狮城|广新|sg|singapore" }
  - { name: P-SGP-ULT, <<: *ULT_FILTER, filter: "(?i)新加坡|狮城|广新|sg|singapore" }

  # 香港
  - { name: P-HK, <<: *SELECT_FILTER, filter: "(?i)港|hk|hongkong|hong kong" }
  - { name: P-HK-FB, <<: *FB_FILTER, filter: "(?i)港|hk|hongkong|hong kong" }
  - { name: P-HK-ULT, <<: *ULT_FILTER, filter: "(?i)港|hk|hongkong|hong kong" }

  # 美国
  - { name: P-US, <<: *SELECT_FILTER, filter: "(?i)美国|广美|us|usa|united states" }
  - { name: P-US-FB, <<: *FB_FILTER, filter: "(?i)美国|广美|us|usa|united states" }
  - { name: P-US-ULT, <<: *ULT_FILTER, filter: "(?i)美国|广美|us|usa|united states" }

  # 日本
  - { name: P-JP, <<: *SELECT_FILTER, filter: "(?i)日本|广日|jp|japan" }
  - { name: P-JP-FB, <<: *FB_FILTER, filter: "(?i)日本|广日|jp|japan" }
  - { name: P-JP-ULT, <<: *ULT_FILTER, filter: "(?i)日本|广日|jp|japan" }

  # 韩国
  - { name: P-KR, <<: *SELECT_FILTER, filter: "(?i)韩国|广韩|kr|korea" }
  - { name: P-KR-FB, <<: *FB_FILTER, filter: "(?i)韩国|广韩|kr|korea" }
  - { name: P-KR-ULT, <<: *ULT_FILTER, filter: "(?i)韩国|广韩|kr|korea" }

  # 土耳其
  # - { name: 土耳其, <<: *SELECT_FILTER, filter: "(?i)土耳其|tr|turkey" }
  # - { name: 土耳其-FB, <<: *FB_FILTER, filter: "(?i)土耳其|tr|turkey" }
  # - { name: 土耳其-ULT, <<: *ULT_FILTER, filter: "(?i)土耳其|tr|turkey" }

  # 印度
  # - { name: 印度, <<: *SELECT_FILTER, filter: "(?i)印度|in|india" }
  # - { name: 印度-FB, <<: *FB_FILTER, filter: "(?i)印度|in|india" }
  # - { name: 印度-ULT, <<: *ULT_FILTER, filter: "(?i)印度|in|india" }

  # 全部
  - { name: All-Proxy-Nodes, <<: *SELECT_FILTER }

  # 代理选择
  - { name: P-Proxy, type: select, proxies: [ P-TW-ULT, P-SGP-ULT, P-HK-ULT, P-US-ULT, P-JP-ULT, P-KR-ULT $PROVIDER_PROXY_NAME_LIST,P-TW, P-SGP, P-HK, P-US, P-JP, P-KR, P-TW-FB, P-SGP-FB, P-HK-FB, P-US-FB, P-JP-FB, P-KR-FB,  All-Proxy-Nodes]}
  - { name: P-AI, type: select, proxies: [ P-TW-ULT, P-SGP-ULT, P-HK-ULT, P-US-ULT, P-JP-ULT, P-KR-ULT $PROVIDER_PROXY_NAME_LIST,P-TW, P-SGP, P-HK, P-US, P-JP, P-KR, P-TW-FB, P-SGP-FB, P-HK-FB, P-US-FB, P-JP-FB, P-KR-FB,  All-Proxy-Nodes]}
  - {
      name: P-Telegram,
      type: select,
      proxies:
        [
          P-TW-ULT,
          P-SGP-ULT,
          P-HK-ULT,
          P-US-ULT,
          P-JP-ULT,
          P-KR-ULT,
          P-TW,
          P-SGP,
          P-HK,
          P-US,
          P-JP,
          P-KR,
          P-TW-FB,
          P-SGP-FB,
          P-HK-FB,
          P-US-FB,
          P-JP-FB,
          P-KR-FB,
          All-Proxy-Nodes,
        ],
    }

  # 直连
  - { name: P-Direct, type: select, proxies: [DIRECT, P-Proxy] }

  # 默认
  - { name: P-Default, type: select, proxies: [P-Proxy, DIRECT] }

rule-providers:
  telegram-ipcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt"
    path: ./rules/telegram-ipcidr.yaml
    interval: 86400

  proxy-domain:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt"
    path: ./rules/proxy-domain.yaml
    interval: 86400

  direct-domain:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt"
    path: ./rules/direct-domain.yaml
    interval: 86400

  direct-ipcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt"
    path: ./rules/direct-ipcidr.yaml
    interval: 86400

  private-domain:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt"
    path: ./rules/private-domain.yaml
    interval: 86400

  private-ipcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt"
    path: ./rules/private-ipcidr.yaml
    interval: 86400

  applications:
    type: http
    behavior: classical
    url: "https://raw.githubusercontent.com/tunnel-collections/t-rules/main/app-direct.yaml"
    path: ./rules/applications.yaml
    interval: 86400

  own-cn-domain:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/tunnel-collections/t-rules/main/own-cn-domain.list"
    path: ./rules/own-cn-domain.list
    interval: 86400

  own-us-domain:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/tunnel-collections/t-rules/main/own-us-domain.list"
    path: ./rules/own-us-domain.list
    interval: 86400
EOF


# config rules
#####################################################################################################################
cat >> ${CONFIG_PATH} << \EOF
rules:
  # 基于先域名后 IP 的规则

EOF




if [ "$ENABLE_DIRECT_PROXY" = "1" ]; then
  # 读取 proxies 目录下的文件
  for proxy_file in $PARENT_DIR/data/proxies/*; do
      # 将代理文件中的 server ，添加到配置文件中
      cat $proxy_file 2>/dev/null |grep "server" | grep -oE 'server:\s*[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+\.?' |sed  's#server:\s*##g' | awk '!a[$0]++' | sed 's/^/\  -\ DOMAIN,/g' | sed 's/$/,DIRECT #节点绕过/g' >> ${CONFIG_PATH}
  done
fi

cat >> ${CONFIG_PATH} << \EOF
  # 国外域名走代理
  - RULE-SET,proxy-domain,P-Proxy
  - RULE-SET,telegram-ipcidr,P-Telegram
  - RULE-SET,own-us-domain,P-AI
  - GEOSITE,category-porn,P-JP-ULT
  - GEOIP,JP,P-JP-ULT

  # 内网域名走直连，路由器走 ipset
  - RULE-SET,private-domain,DIRECT

  # 国内直连
  - RULE-SET,own-cn-domain,DIRECT
  - RULE-SET,direct-domain,DIRECT
  - DOMAIN-KEYWORD,com.cn,DIRECT

  # ip 必须加 no-resolve，防止 dns 泄漏
  - RULE-SET,private-ipcidr,DIRECT,no-resolve

  # 国内 IP 走直连，路由器走 ipset
  #- RULE-SET,direct-ipcidr,DIRECT,no-resolve
  - GEOIP,CN,DIRECT,no-resolve

  # 默认走 代理
  - MATCH,P-Default
EOF
