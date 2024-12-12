

```bash
sudo apt install ipset
```
## 一、生成配置文件

```bash
cd shell
./gen.config.sh 
```

## 二、生成启动systemd服务文件

```bash
cd shell
./gen.systemd.service.sh
```

## 三、生成 iptables 规则

```bash
cd shell
./gen.iptables.sh
```

## 四、启动服务

```bash
./bin/mihomo-linux-amd64-compatible-go120-v1.18.10 -d data -f data/m.yaml
```

## 五、生成 mosdns 配置文件

```bash
cd shell
./update.proxy.domain.sh
```
