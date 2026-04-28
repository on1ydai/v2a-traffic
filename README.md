# v2a-traffic

给 `v2ray-agent` 自建节点添加轻量级流量显示的一键脚本。

适合已经使用 `v2ray-agent` 搭建 `VLESS + Reality` 节点的低配 VPS。无需安装 3x-ui、Marzban 等面板，通过 `vnStat` 统计 VPS 网卡流量，并自动生成适配不同客户端的订阅地址。

---

## 功能特性

* 自动检测 v2ray-agent 订阅目录
* 自动检测 Nginx 订阅配置
* 自动检测订阅端口
* 自动检测公网 IP
* 自动读取已有订阅 token
* 自动安装依赖：`vnstat`、`jq`、`curl`、`python3-yaml`
* 自动添加 `subscription-userinfo` 响应头
* 自动生成 Shadowrocket 专用订阅 `/sr/`
* 自动生成 Clash Meta for Android 专用订阅 `/cma/`
* 自动写入 cron，每 5 分钟刷新一次流量统计
* 提供管理菜单，可修改参数、刷新订阅、查看订阅地址、卸载

---

## 客户端支持

| 客户端                           | 订阅地址                         | 显示方式               |
| ----------------------------- | ---------------------------- | ------------------ |
| Clash Verge / Clash Verge Rev | `/s/clashMetaProfiles/token` | 配置页显示流量进度条         |
| Shadowrocket / 小火箭            | `/sr/token`                  | 节点列表显示“剩余流量：xxxG”  |
| Clash Meta for Android        | `/cma/token`                 | 节点选择里显示“剩余流量：xxxG” |

说明：

Clash Verge 通常能直接读取 `subscription-userinfo` 响应头并显示在配置页。Shadowrocket 和 Clash Meta for Android 在不同版本中表现不完全一致，所以脚本会给它们生成专用订阅，通过额外添加一个“剩余流量：xxxG”节点来稳定显示流量。

---

## 一键安装

SSH 登录 VPS 后执行：

```bash
curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh -o /usr/local/bin/v2a-traffic && chmod +x /usr/local/bin/v2a-traffic && v2a-traffic
```

如果你想先查看脚本内容再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh -o v2a-traffic.sh
less v2a-traffic.sh
bash v2a-traffic.sh
```

---

## 安装前提

你需要满足：

1. VPS 已安装 `v2ray-agent`。
2. 已通过 v2ray-agent 成功生成订阅。
3. 订阅目录存在：

```bash
ls -lah /etc/v2ray-agent/subscribe
```

通常会看到：

```text
clashMeta
clashMetaProfiles
default
sing-box
sing-box_profiles
```

4. 使用 root 用户运行脚本。

---

## 安装时需要填写什么？

脚本会自动检测大多数信息，只有 VPS 套餐相关参数需要你填写。

| 项目          | 示例                    | 说明                           |
| ----------- | --------------------- | ---------------------------- |
| 访问协议        | `http`                | 无域名 v2ray-agent 订阅通常是 `http` |
| VPS IP / 域名 | `168.93.214.117`      | 脚本会自动检测公网 IP，可直接回车           |
| 订阅端口        | `22289`               | 脚本会尝试从 Nginx 配置中自动检测         |
| 套餐总流量 GiB   | `250`                 | 250G 写 `250`，1T 写 `1024`     |
| 计费方式        | `both`                | 入站 + 出站都算；只算出站则选 `out`       |
| 每月重置日       | `23`                  | 流量每月几号重置就填几号                 |
| 当前已用流量 GiB  | `25`                  | vnStat 从安装后才开始统计，旧流量用这个补齐    |
| 到期 / 重置日期   | `2026-05-23 00:00:00` | 可留空                          |
| 是否生成小火箭订阅   | `Y`                   | 推荐开启                         |
| 是否生成安卓订阅    | `Y`                   | 推荐开启                         |

---

## 安装完成后

脚本会输出类似：

```text
Clash Verge / Clash Verge Rev：
  http://IP:端口/s/clashMetaProfiles/token

Shadowrocket / 小火箭：
  http://IP:端口/sr/token

Clash Meta for Android：
  http://IP:端口/cma/token
```

按客户端导入对应订阅即可。

---

## 后续管理

安装完成后，可以直接运行：

```bash
v2a-traffic
```

管理菜单包含：

```text
1) 安装 / 更新流量订阅显示
2) 修改套餐流量参数
3) 立即重新生成订阅
4) 查看当前订阅地址
5) 卸载本工具
0) 退出
```

也可以直接手动刷新流量订阅：

```bash
v2a-traffic-update
```

---

## 验证是否成功

### 1. 验证 Clash Verge 响应头

把地址换成你的实际订阅地址：

```bash
curl -sI "http://IP:端口/s/clashMetaProfiles/token" | tr -d '\r' | grep -i subscription-userinfo
```

正常会看到：

```text
subscription-userinfo: upload=xxx; download=xxx; total=xxx; expire=xxx
```

### 2. 验证 Shadowrocket 订阅

```bash
curl -s "http://IP:端口/sr/token" | base64 -d | head -n 5
```

正常会看到类似：

```text
vless://...#剩余流量：223G
vless://...#原本节点名称
```

### 3. 验证 Clash Meta for Android provider

```bash
curl -s "http://IP:端口/cma-provider/token" | grep -n "剩余流量" | head
```

正常会看到：

```text
2:- name: 剩余流量：223G
```

---

## 原理简介

机场订阅显示流量的核心通常是 HTTP 响应头：

```http
subscription-userinfo: upload=123; download=456; total=789; expire=1779508800
```

字段含义：

| 字段         | 含义          | 单位       |
| ---------- | ----------- | -------- |
| `upload`   | 已上传流量       | bytes    |
| `download` | 已下载流量       | bytes    |
| `total`    | 套餐总流量       | bytes    |
| `expire`   | 到期时间 / 重置时间 | Unix 时间戳 |

本脚本使用 `vnStat` 统计 VPS 网卡流量，再由 Nginx 返回 `subscription-userinfo` 响应头。

同时，为了兼容 Shadowrocket 和 Clash Meta for Android，脚本会生成专用订阅，把第一个真实节点复制一份并改名为：

```text
剩余流量：xxxG
```

这样即使客户端不显示配置卡片流量，也能在节点列表里看到剩余流量。

---

## 目录说明

安装后会生成：

```text
/etc/v2a-traffic/config.env              # 配置文件
/usr/local/bin/v2a-traffic               # 管理菜单
/usr/local/bin/v2a-traffic-update        # 更新脚本
/etc/cron.d/v2a-traffic                  # 定时任务
/var/lib/v2a-traffic/                    # 生成的订阅缓存
/etc/nginx/snippets/xray_subscription_userinfo.conf
```

---

## 卸载

运行管理菜单：

```bash
v2a-traffic
```

选择：

```text
5) 卸载本工具
```

卸载会删除脚本、配置、定时任务和订阅缓存。

注意：脚本会自动备份 Nginx 配置，但卸载时不会自动回滚 Nginx 配置，避免误删用户自定义配置。如果需要完全恢复，可以手动恢复 `/etc/nginx/conf.d/subscribe.conf` 附近的 `.bak.v2a-traffic.*` 备份。

---

## 常见问题

### Clash Verge 没显示流量

先确认响应头是否存在：

```bash
curl -sI "http://IP:端口/s/clashMetaProfiles/token" | tr -d '\r' | grep -i subscription-userinfo
```

如果没有输出，检查 Nginx 配置是否成功写入：

```bash
nginx -T 2>/dev/null | grep -n "xray_subscription_userinfo"
nginx -t
```

### 小火箭提示无法获取订阅节点

检查 `/sr/` 是否能解出节点：

```bash
curl -s "http://IP:端口/sr/token" | base64 -d | head -n 5
```

能看到 `vless://` 说明订阅格式正常。

### Clash Meta for Android 看不到剩余流量节点

检查 provider：

```bash
curl -s "http://IP:端口/cma-provider/token" | grep -n "剩余流量" | head
```

如果服务端有，但客户端没有，删除配置重新添加，或清理 Clash Meta for Android 的配置缓存。

### 流量和 VPS 后台不完全一致

这是正常现象，常见原因包括：

1. `vnStat` 从安装后才开始统计。
2. VPS 商家可能按十进制 GB 统计，脚本按 GiB 计算。
3. 商家可能只算出站，而你选择了双向计费。
4. VPS 后台可能有统计延迟。

可以通过管理菜单修改“当前已用流量 GiB”来校准。

---

## 安全提醒

* 订阅链接里的 token 非常重要，不要公开泄露。
* 截图时请打码 IP、token、UUID、公钥等敏感信息。
* 建议先查看脚本内容再执行，尤其是在生产环境中。

---

## 免责声明

本项目仅用于自有 VPS 的流量统计和订阅展示。请遵守当地法律法规以及 VPS 服务商的使用条款。
