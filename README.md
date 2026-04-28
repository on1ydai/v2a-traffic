# v2a-traffic

<p align="center">
  <strong>一条命令，为 v2ray-agent 自建节点添加流量显示</strong>
</p>

<p align="center">
  轻量 · 自动化 · 低配 VPS 友好 · 无需安装面板
</p>

<p align="center">
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white">
  <img alt="v2ray-agent" src="https://img.shields.io/badge/For-v2ray--agent-7c9cff?style=flat-square">
  <img alt="vnStat" src="https://img.shields.io/badge/Traffic-vnStat-7df0c4?style=flat-square">
  <img alt="Nginx" src="https://img.shields.io/badge/Nginx-Subscription-009639?style=flat-square&logo=nginx&logoColor=white">
</p>

---

## 项目简介

`v2a-traffic` 是一个给 **v2ray-agent 自建节点** 添加流量显示的一键脚本。

如果你已经通过 `v2ray-agent` 搭建了 `VLESS + Reality` 节点，但每次想看流量都要登录 VPS 商家后台，那么这个脚本可以帮你把流量信息直接显示到客户端订阅里。

它适合这些场景：

- 你已经在用 `v2ray-agent`
- VPS 配置较低，比如 512MB 内存
- 不想安装 3x-ui、Marzban、Xboard 等面板
- 想保留现有节点配置
- 想像机场订阅一样看到流量使用情况

---

## 最终效果

| 客户端 | 订阅地址 | 显示方式 |
|---|---|---|
| Clash Verge / Clash Verge Rev | `/s/clashMetaProfiles/token` | 配置页显示流量进度条 |
| Shadowrocket / 小火箭 | `/sr/token` | 节点列表显示 `剩余流量：xxxG` |
| Clash Meta for Android | `/cma/token` | 节点选择中显示 `剩余流量：xxxG` |

说明：

- Clash Verge 通常可以直接读取 `subscription-userinfo` 响应头，所以可以显示在配置页。
- Shadowrocket 和 Clash Meta for Android 不同版本的显示逻辑不完全一致，所以脚本会额外生成专用订阅，通过“剩余流量节点”的方式稳定显示。

---

## 一键安装

SSH 登录 VPS 后执行：

```bash
curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh -o /usr/local/bin/v2a-traffic && chmod +x /usr/local/bin/v2a-traffic && v2a-traffic
```

安装完成后，以后可以直接运行：

```bash
v2a-traffic
```

打开管理菜单。

---

## 先查看再执行

如果你不想直接执行远程脚本，可以先下载并查看内容：

```bash
curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh -o /usr/local/bin/v2a-traffic
less /usr/local/bin/v2a-traffic
chmod +x /usr/local/bin/v2a-traffic
v2a-traffic
```

---

## 安装前提

运行前请确认：

1. VPS 已经安装 `v2ray-agent`
2. 已通过 `v2ray-agent` 成功生成订阅
3. Nginx 订阅端口可以正常访问
4. 使用 `root` 用户执行脚本

可以先检查订阅目录：

```bash
ls -lah /etc/v2ray-agent/subscribe
```

通常会看到类似：

```text
clashMeta
clashMetaProfiles
default
sing-box
sing-box_profiles
```

---

## 脚本会自动做什么？

`v2a-traffic` 会自动完成以下操作：

- 检测 `v2ray-agent` 订阅目录
- 检测 Nginx 订阅配置
- 检测订阅端口
- 检测公网 IP
- 读取已有订阅 token
- 安装依赖：
  - `vnstat`
  - `jq`
  - `curl`
  - `python3-yaml`
- 生成流量统计更新脚本
- 给原订阅添加 `subscription-userinfo` 响应头
- 生成 Shadowrocket 专用订阅 `/sr/`
- 生成 Clash Meta for Android 专用订阅 `/cma/`
- 写入 cron 定时任务，每 5 分钟刷新一次流量统计
- 输出各客户端可用的订阅地址

---

## 安装时需要填写什么？

脚本会自动检测大部分信息，只有 VPS 套餐相关信息需要你自己填写。

| 项目 | 示例 | 说明 |
|---|---|---|
| 访问协议 | `http` | 无域名 v2ray-agent 订阅通常是 `http` |
| VPS IP / 域名 | `168.93.214.117` | 脚本会自动检测公网 IP，可直接回车 |
| 订阅端口 | `22289` | 脚本会尽量从 Nginx 配置中自动检测 |
| 套餐总流量 GiB | `250` | 250G 写 `250`，1T 写 `1024` |
| 计费方式 | `both` / `out` | `both` 表示入站 + 出站都算；`out` 表示只算出站 |
| 每月重置日 | `23` | 流量每月几号重置就填几号 |
| 当前已用流量 GiB | `25` | 用于补上安装 vnStat 前已经用掉的流量 |
| 到期 / 重置日期 | `2026-05-23 00:00:00` | 可留空 |
| 是否生成小火箭订阅 | `Y` | 推荐开启 |
| 是否生成安卓订阅 | `Y` | 推荐开启 |

---

## 安装完成后怎么用？

脚本跑完后，会输出类似下面的订阅地址：

```text
Clash Verge / Clash Verge Rev：
  http://IP:端口/s/clashMetaProfiles/token

Shadowrocket / 小火箭：
  http://IP:端口/sr/token

Clash Meta for Android：
  http://IP:端口/cma/token
```

按客户端导入对应订阅即可。

### Clash Verge / Clash Verge Rev

使用：

```text
http://IP:端口/s/clashMetaProfiles/token
```

它会读取订阅响应头里的流量信息，在配置页显示流量进度条。

### Shadowrocket / 小火箭

使用：

```text
http://IP:端口/sr/token
```

它会在节点列表中多出一个：

```text
剩余流量：xxxG
```

这个节点只是用于查看剩余流量，实际连接时继续选择你原来的真实节点。

### Clash Meta for Android

使用：

```text
http://IP:端口/cma/token
```

它会在节点选择中多出一个：

```text
剩余流量：xxxG
```

同样，这个节点只是用于查看剩余流量，真实使用时继续选择原节点。

---

## 后续管理

安装完成后，可以直接运行：

```bash
v2a-traffic
```

会看到管理菜单：

```text
1) 安装 / 更新流量订阅显示
2) 修改套餐流量参数
3) 立即重新生成订阅
4) 查看当前订阅地址
5) 卸载本工具
0) 退出
```

如果只想手动刷新一次流量和订阅文件，可以运行：

```bash
v2a-traffic-update
```

---

## 验证是否成功

### 1. 验证 Clash Verge 响应头

把地址换成你自己的实际订阅地址：

```bash
curl -sI "http://IP:端口/s/clashMetaProfiles/token" | tr -d '\r' | grep -i subscription-userinfo
```

正常会看到类似：

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

正常会看到类似：

```text
2:- name: 剩余流量：223G
```

---

## 原理简介

这个方案的核心有两部分。

### 1. 使用 vnStat 统计 VPS 网卡流量

`vnStat` 是一个轻量级流量统计工具，它会统计 VPS 网卡的入站和出站流量。

相比安装面板，`vnStat` 更适合低配 VPS，因为它占用资源很少。

### 2. 通过订阅响应头告诉客户端流量信息

很多客户端或机场面板会使用这个 HTTP 响应头展示流量：

```http
subscription-userinfo: upload=123; download=456; total=789; expire=1779508800
```

字段含义：

| 字段 | 含义 | 单位 |
|---|---|---|
| `upload` | 已上传流量 | bytes |
| `download` | 已下载流量 | bytes |
| `total` | 套餐总流量 | bytes |
| `expire` | 到期时间 / 重置时间 | Unix 时间戳 |

Clash Verge 可以直接读取这个响应头，所以能在配置页显示流量。

Shadowrocket 和 Clash Meta for Android 的不同版本表现不完全一致，所以脚本会给它们额外生成专用订阅，把一个真实节点复制一份并改名为：

```text
剩余流量：xxxG
```

这样即使客户端不显示配置页流量，也能在节点列表里看到剩余流量。

---

## 安装后生成的文件

```text
/etc/v2a-traffic/config.env
/usr/local/bin/v2a-traffic
/usr/local/bin/v2a-traffic-update
/etc/cron.d/v2a-traffic
/var/lib/v2a-traffic/
/etc/nginx/snippets/xray_subscription_userinfo.conf
```

说明：

| 路径 | 作用 |
|---|---|
| `/etc/v2a-traffic/config.env` | 配置文件 |
| `/usr/local/bin/v2a-traffic` | 管理菜单命令 |
| `/usr/local/bin/v2a-traffic-update` | 更新流量和订阅文件的脚本 |
| `/etc/cron.d/v2a-traffic` | 定时任务 |
| `/var/lib/v2a-traffic/` | 生成的专用订阅缓存 |
| `/etc/nginx/snippets/xray_subscription_userinfo.conf` | Nginx 响应头配置 |

---

## 卸载

运行：

```bash
v2a-traffic
```

选择：

```text
5) 卸载本工具
```

卸载会删除：

- 脚本本体
- 配置文件
- 定时任务
- 生成的订阅缓存

注意：脚本会自动备份 Nginx 配置，但卸载时不会自动回滚 Nginx 配置，避免误删用户自己的自定义改动。如果需要完全恢复，可以手动恢复 `/etc/nginx/conf.d/subscribe.conf` 附近的 `.bak.v2a-traffic.*` 备份文件。

---

## 常见问题

### Clash Verge 没显示流量

先检查响应头是否存在：

```bash
curl -sI "http://IP:端口/s/clashMetaProfiles/token" | tr -d '\r' | grep -i subscription-userinfo
```

如果没有输出，检查 Nginx 配置是否成功写入：

```bash
nginx -T 2>/dev/null | grep -n "xray_subscription_userinfo"
nginx -t
```

---

### Shadowrocket 提示无法获取订阅节点

检查 `/sr/` 是否能解出节点：

```bash
curl -s "http://IP:端口/sr/token" | base64 -d | head -n 5
```

如果能看到 `vless://`，说明订阅格式通常是正常的。

---

### Clash Meta for Android 看不到“剩余流量”节点

先检查服务端 provider 是否已经生成：

```bash
curl -s "http://IP:端口/cma-provider/token" | grep -n "剩余流量" | head
```

如果服务端有，但客户端没有显示，可以尝试：

- 删除原配置重新添加
- 清理客户端缓存后重新订阅
- 手动运行 `v2a-traffic-update` 后再更新订阅

---

### 流量和 VPS 后台不完全一致

这是正常现象，可能原因包括：

1. `vnStat` 从安装后才开始统计
2. VPS 商家可能按十进制 GB 统计，而脚本按 GiB 计算
3. 商家可能只计算出站流量，而你选择了双向统计
4. VPS 后台本身可能存在统计延迟

如果想尽量对齐，可以通过管理菜单修改“当前已用流量 GiB”来做校准。

---

### 之前用旧命令安装，为什么没有 `v2a-traffic` 命令？

如果之前用的是这种临时执行方式：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh)
```

可能不会把脚本保存到 `/usr/local/bin/v2a-traffic`。

修复方法：

```bash
curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh -o /usr/local/bin/v2a-traffic
chmod +x /usr/local/bin/v2a-traffic
v2a-traffic
```

---

## 更新脚本

重新拉取最新版并打开菜单：

```bash
curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh -o /usr/local/bin/v2a-traffic
chmod +x /usr/local/bin/v2a-traffic
v2a-traffic
```

---

## 安全提醒

- 订阅链接里的 token 非常重要，请不要公开泄露
- 发布截图时请打码：
  - IP
  - token
  - UUID
  - Reality 公钥
  - 端口
- 建议在生产环境中先查看脚本内容，再执行

---

## 免责声明

本项目仅用于自有 VPS 的流量统计与订阅展示。

请遵守当地法律法规以及 VPS 服务商的使用条款。

---

## Star History

如果这个项目对你有帮助，欢迎点个 Star。

也欢迎提交 Issue 或 PR，一起完善这个脚本。
