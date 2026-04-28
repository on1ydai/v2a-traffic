# v2a-traffic

> 一条命令，为 `v2ray-agent` 自建节点添加流量显示。  
> 轻量、自动化、适合低配 VPS。支持 **Clash Verge**、**Shadowrocket**、**Clash Meta for Android**。

---

## ✨ 项目简介

如果你已经用 `v2ray-agent` 搭建了 `VLESS + Reality` 节点，平时想看流量使用情况，通常只能去 VPS 商家后台查看，比较麻烦。

`v2a-traffic` 的目标就是解决这个问题：

- **Clash Verge / Clash Verge Rev**：在配置页显示流量信息
- **Shadowrocket / 小火箭**：在节点列表中显示 `剩余流量：xxxG`
- **Clash Meta for Android**：在节点选择中显示 `剩余流量：xxxG`

整个方案不依赖 3x-ui、Marzban 这类面板，更适合：

- 已经在用 `v2ray-agent`
- 机器配置较低，比如 `512MB` 内存
- 想保留现有自建节点方案
- 想要像机场订阅那样看到流量显示

---

## 🚀 一键安装

SSH 登录 VPS 后执行：

```bash
curl -fsSL https://raw.githubusercontent.com/on1ydai/v2a-traffic/main/v2a-traffic.sh -o /usr/local/bin/v2a-traffic && chmod +x /usr/local/bin/v2a-traffic && v2a-traffic
