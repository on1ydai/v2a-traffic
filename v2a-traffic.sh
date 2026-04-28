#!/usr/bin/env bash
# v2a-traffic.sh
# 一键给 v2ray-agent 订阅添加流量显示：Clash Verge / Shadowrocket / Clash Meta for Android

set -euo pipefail

APP_NAME="v2a-traffic"
CONFIG_DIR="/etc/${APP_NAME}"
CONFIG_FILE="${CONFIG_DIR}/config.env"
UPDATE_BIN="/usr/local/bin/v2a-traffic-update"
MANAGER_BIN="/usr/local/bin/v2a-traffic"
CRON_FILE="/etc/cron.d/v2a-traffic"
DATA_DIR="/var/lib/${APP_NAME}"
HEADER_FILE="/etc/nginx/snippets/xray_subscription_userinfo.conf"

red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
blue() { echo -e "\033[36m$*\033[0m"; }

pause() {
  echo
  read -rp "按回车继续..." _ || true
}

die() {
  red "错误：$*"
  exit 1
}

need_root() {
  [ "$(id -u)" = "0" ] || die "请使用 root 用户运行"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_deps() {
  green "==> 安装依赖"

  if has_cmd apt; then
    apt update
    apt install -y vnstat jq curl nginx python3 python3-yaml
  elif has_cmd dnf; then
    dnf install -y vnstat jq curl nginx python3 python3-pyyaml
  elif has_cmd yum; then
    yum install -y epel-release || true
    yum install -y vnstat jq curl nginx python3 python3-pyyaml
  else
    die "暂不支持当前系统包管理器，请使用 Debian/Ubuntu/CentOS/RHEL 系系统"
  fi

  systemctl enable --now vnstat >/dev/null 2>&1 || true
}

check_v2ray_agent() {
  [ -d /etc/v2ray-agent/subscribe ] || die "没有找到 /etc/v2ray-agent/subscribe，请确认已安装 v2ray-agent 并生成过订阅"
}

detect_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

detect_nginx_sub_conf() {
  grep -R "alias /etc/v2ray-agent/subscribe" -l /etc/nginx 2>/dev/null | grep -v '\.bak' | head -n 1 || true
}

detect_sub_port() {
  local conf="$1"
  [ -f "$conf" ] || return 0
  grep -oE 'listen[[:space:]]+(\[::\]:)?[0-9]+' "$conf" | head -n 1 | grep -oE '[0-9]+$' || true
}

detect_public_ip() {
  curl -4 -fsS --connect-timeout 5 https://api.ipify.org 2>/dev/null \
    || curl -4 -fsS --connect-timeout 5 https://ifconfig.me 2>/dev/null \
    || hostname -I | awk '{print $1}'
}

shell_quote() {
  printf '%q' "$1"
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

save_config() {
  mkdir -p "$CONFIG_DIR"
  cat >"$CONFIG_FILE" <<EOF
SCHEME=$(shell_quote "$SCHEME")
HOST=$(shell_quote "$HOST")
PORT=$(shell_quote "$PORT")
PUBLIC_BASE=$(shell_quote "$PUBLIC_BASE")
TOTAL_GB=$(shell_quote "$TOTAL_GB")
COUNT_MODE=$(shell_quote "$COUNT_MODE")
BILLING_DAY=$(shell_quote "$BILLING_DAY")
OFFSET_USED_GB=$(shell_quote "$OFFSET_USED_GB")
EXPIRE_TS=$(shell_quote "$EXPIRE_TS")
PROFILE_TITLE=$(shell_quote "$PROFILE_TITLE")
ENABLE_SR=$(shell_quote "$ENABLE_SR")
ENABLE_CMA=$(shell_quote "$ENABLE_CMA")
EOF
}

ask_config() {
  local sub_conf sub_port public_ip default_scheme default_host default_port default_total default_mode default_billing default_offset default_expire default_title default_sr default_cma

  sub_conf="$(detect_nginx_sub_conf)"
  sub_port="$(detect_sub_port "$sub_conf")"
  public_ip="$(detect_public_ip)"

  default_scheme="${SCHEME:-http}"
  default_host="${HOST:-$public_ip}"
  default_port="${PORT:-${sub_port:-22289}}"
  default_total="${TOTAL_GB:-250}"
  default_mode="${COUNT_MODE:-both}"
  default_billing="${BILLING_DAY:-1}"
  default_offset="${OFFSET_USED_GB:-0}"
  default_title="${PROFILE_TITLE:-VPS}"
  default_sr="${ENABLE_SR:-1}"
  default_cma="${ENABLE_CMA:-1}"

  echo
  yellow "请填写 VPS 套餐与订阅信息。直接回车使用默认值。"
  echo

  read -rp "访问协议 [${default_scheme}]: " SCHEME
  SCHEME="${SCHEME:-$default_scheme}"

  read -rp "VPS IP / 域名 [${default_host}]: " HOST
  HOST="${HOST:-$default_host}"

  read -rp "订阅端口 [${default_port}]: " PORT
  PORT="${PORT:-$default_port}"

  read -rp "套餐总流量 GiB，例如 250 / 500 / 1024 [${default_total}]: " TOTAL_GB
  TOTAL_GB="${TOTAL_GB:-$default_total}"

  echo
  echo "计费方式："
  echo "  1) 入站 + 出站都算，常见于多数 VPS 商家"
  echo "  2) 只算出站"
  if [ "$default_mode" = "out" ]; then
    read -rp "请选择 [2]: " mode_choice
    mode_choice="${mode_choice:-2}"
  else
    read -rp "请选择 [1]: " mode_choice
    mode_choice="${mode_choice:-1}"
  fi
  case "$mode_choice" in
    2|out|OUT) COUNT_MODE="out" ;;
    *) COUNT_MODE="both" ;;
  esac

  read -rp "每月流量重置日，例如 1 或 23 [${default_billing}]: " BILLING_DAY
  BILLING_DAY="${BILLING_DAY:-$default_billing}"

  read -rp "当前 VPS 后台已用流量 GiB，新机器填 0 [${default_offset}]: " OFFSET_USED_GB
  OFFSET_USED_GB="${OFFSET_USED_GB:-$default_offset}"

  read -rp "到期 / 重置日期，可空，例如 2026-05-23 00:00:00: " default_expire
  if [ -n "$default_expire" ]; then
    EXPIRE_TS="$(date -d "$default_expire" +%s)"
  else
    EXPIRE_TS="${EXPIRE_TS:-}"
  fi

  read -rp "订阅文件名 [${default_title}]: " PROFILE_TITLE
  PROFILE_TITLE="${PROFILE_TITLE:-$default_title}"

  echo
  read -rp "是否生成 Shadowrocket / 小火箭专用订阅？[Y/n]: " yn_sr
  case "${yn_sr:-Y}" in
    n|N|no|NO) ENABLE_SR=0 ;;
    *) ENABLE_SR=1 ;;
  esac

  read -rp "是否生成 Clash Meta for Android 专用订阅？[Y/n]: " yn_cma
  case "${yn_cma:-Y}" in
    n|N|no|NO) ENABLE_CMA=0 ;;
    *) ENABLE_CMA=1 ;;
  esac

  PUBLIC_BASE="${SCHEME}://${HOST}:${PORT}"
  save_config

  green "配置已保存：$CONFIG_FILE"
}

write_update_script() {
  green "==> 写入更新脚本：$UPDATE_BIN"

  cat >"$UPDATE_BIN" <<'UPDATER'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/v2a-traffic/config.env"
HEADER_FILE="/etc/nginx/snippets/xray_subscription_userinfo.conf"
SR_OUT_DIR="/var/lib/v2a-traffic/shadowrocket-sub"
CMA_PROFILE_OUT_DIR="/var/lib/v2a-traffic/cma-sub"
CMA_PROVIDER_OUT_DIR="/var/lib/v2a-traffic/cma-provider"

[ -f "$CONFIG_FILE" ] || { echo "配置文件不存在：$CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

IFACE="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -n "$IFACE" ] || { echo "无法检测默认网卡" >&2; exit 1; }

mkdir -p /etc/nginx/snippets /var/lib/v2a-traffic

json="$(vnstat --json -i "$IFACE" 2>/dev/null || echo '{}')"

today_day="$(date +%-d)"
billing_day_padded="$(printf "%02d" "$BILLING_DAY")"

if [ "$today_day" -ge "$BILLING_DAY" ]; then
  cycle_month="$(date +%Y-%m)"
else
  cycle_month="$(date -d "$(date +%Y-%m-15) -1 month" +%Y-%m)"
fi

START_DATE="${cycle_month}-${billing_day_padded}"
START_NUM="$(date -d "$START_DATE" +%Y%m%d)"

RX_BYTES="$(echo "$json" | jq -r --argjson start "$START_NUM" '
  [.interfaces[0].traffic.day[]?
   | select((.date.year * 10000 + .date.month * 100 + .date.day) >= $start)
   | (.rx // 0)
  ] | add // 0
')"

TX_BYTES="$(echo "$json" | jq -r --argjson start "$START_NUM" '
  [.interfaces[0].traffic.day[]?
   | select((.date.year * 10000 + .date.month * 100 + .date.day) >= $start)
   | (.tx // 0)
  ] | add // 0
')"

TOTAL_BYTES=$((TOTAL_GB * 1024 * 1024 * 1024))
OFFSET_BYTES=$((OFFSET_USED_GB * 1024 * 1024 * 1024))

case "$COUNT_MODE" in
  both)
    UPLOAD="$RX_BYTES"
    DOWNLOAD=$((TX_BYTES + OFFSET_BYTES))
    ;;
  out)
    UPLOAD=0
    DOWNLOAD=$((TX_BYTES + OFFSET_BYTES))
    ;;
  *)
    echo "COUNT_MODE must be both or out" >&2
    exit 1
    ;;
esac

USED_BYTES=$((UPLOAD + DOWNLOAD))
LEFT_BYTES=$((TOTAL_BYTES - USED_BYTES))
if [ "$LEFT_BYTES" -lt 0 ]; then
  LEFT_BYTES=0
fi

USED_GB_SHOW="$(awk "BEGIN {printf \"%.1f\", $USED_BYTES/1024/1024/1024}")"
TOTAL_GB_SHOW="$(awk "BEGIN {printf \"%.0f\", $TOTAL_BYTES/1024/1024/1024}")"
LEFT_GB_SHOW="$(awk "BEGIN {printf \"%.0f\", $LEFT_BYTES/1024/1024/1024}")"

if [ -n "${EXPIRE_TS:-}" ]; then
  USERINFO="upload=$UPLOAD; download=$DOWNLOAD; total=$TOTAL_BYTES; expire=$EXPIRE_TS"
else
  USERINFO="upload=$UPLOAD; download=$DOWNLOAD; total=$TOTAL_BYTES"
fi

SAFE_TITLE="${PROFILE_TITLE//\"/}"

cat >"$HEADER_FILE.tmp" <<EOF
add_header subscription-userinfo "$USERINFO" always;
add_header profile-update-interval "6" always;
add_header content-disposition "attachment;filename*=UTF-8''${SAFE_TITLE}" always;
add_header cache-control "private, must-revalidate" always;
add_header expires "-1" always;
EOF

if [ ! -f "$HEADER_FILE" ] || ! cmp -s "$HEADER_FILE.tmp" "$HEADER_FILE"; then
  mv "$HEADER_FILE.tmp" "$HEADER_FILE"
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
else
  rm -f "$HEADER_FILE.tmp"
fi

if [ "${ENABLE_SR:-1}" = "1" ]; then
  SRC_DIR="/etc/v2ray-agent/subscribe/default"
  if [ -d "$SRC_DIR" ]; then
    mkdir -p "$SR_OUT_DIR"
    rm -f "$SR_OUT_DIR"/*
    python3 - "$SRC_DIR" "$SR_OUT_DIR" "剩余流量：${LEFT_GB_SHOW}G" <<'PY'
import sys, base64
from pathlib import Path
from urllib.parse import quote

src_dir = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
info_name = sys.argv[3]
out_dir.mkdir(parents=True, exist_ok=True)

def decode_sub(raw):
    compact = "".join(raw.strip().split())
    try:
        padded = compact + "=" * ((4 - len(compact) % 4) % 4)
        decoded = base64.b64decode(padded).decode("utf-8", errors="ignore")
        if "://" in decoded:
            return decoded
    except Exception:
        pass
    return raw

def encode_sub(text):
    return base64.b64encode(text.encode("utf-8")).decode("ascii")

def rename_node(line, name):
    base = line.split("#", 1)[0]
    return base + "#" + quote(name, safe="")

for src in src_dir.iterdir():
    if not src.is_file():
        continue
    text = decode_sub(src.read_text(errors="ignore"))
    original_lines = []
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith(("STATUS=", "REMARKS=")) and "://" in line:
            original_lines.append(line)
    if not original_lines:
        continue
    info_node = rename_node(original_lines[0], info_name)
    out_text = "\n".join([info_node] + original_lines) + "\n"
    (out_dir / src.name).write_text(encode_sub(out_text) + "\n")
PY
    chmod 755 /var/lib /var/lib/v2a-traffic "$SR_OUT_DIR" 2>/dev/null || true
    chmod 644 "$SR_OUT_DIR"/* 2>/dev/null || true
  fi
fi

if [ "${ENABLE_CMA:-1}" = "1" ]; then
  PROFILE_SRC_DIR="/etc/v2ray-agent/subscribe/clashMetaProfiles"
  PROVIDER_SRC_DIR="/etc/v2ray-agent/subscribe/clashMeta"
  if [ -d "$PROFILE_SRC_DIR" ]; then
    mkdir -p "$CMA_PROFILE_OUT_DIR" "$CMA_PROVIDER_OUT_DIR"
    rm -f "$CMA_PROFILE_OUT_DIR"/* "$CMA_PROVIDER_OUT_DIR"/*
    python3 - "$PROFILE_SRC_DIR" "$PROVIDER_SRC_DIR" "$CMA_PROFILE_OUT_DIR" "$CMA_PROVIDER_OUT_DIR" "剩余流量：${LEFT_GB_SHOW}G" "$PUBLIC_BASE" <<'PY'
import sys, re, copy
from pathlib import Path
import yaml

profile_src_dir = Path(sys.argv[1])
provider_src_dir = Path(sys.argv[2])
profile_out_dir = Path(sys.argv[3])
provider_out_dir = Path(sys.argv[4])
info_name = sys.argv[5]
public_base = sys.argv[6].rstrip("/")
profile_out_dir.mkdir(parents=True, exist_ok=True)
provider_out_dir.mkdir(parents=True, exist_ok=True)

def load_yaml(path):
    try:
        return yaml.safe_load(path.read_text(errors="ignore"))
    except Exception:
        return None

def dump_yaml(path, data):
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")

def add_info_node_to_provider(data):
    if isinstance(data, dict) and isinstance(data.get("proxies"), list):
        proxies = data["proxies"]
        wrapper = data
    elif isinstance(data, list):
        proxies = data
        wrapper = None
    else:
        return None
    proxies = [p for p in proxies if not (isinstance(p, dict) and str(p.get("name", "")).startswith("剩余流量："))]
    real = [p for p in proxies if isinstance(p, dict)]
    if not real:
        return None
    info_proxy = copy.deepcopy(real[0])
    info_proxy["name"] = info_name
    new_proxies = [info_proxy] + proxies
    if wrapper is not None:
        wrapper["proxies"] = new_proxies
        return wrapper
    return new_proxies

def rewrite_profile_provider_urls(data):
    if not isinstance(data, dict):
        return data, False
    changed = False
    providers = data.get("proxy-providers")
    if isinstance(providers, dict):
        for name, provider in providers.items():
            if not isinstance(provider, dict):
                continue
            url = str(provider.get("url", ""))
            m = re.search(r"/s/clashMeta/([A-Za-z0-9]+)", url)
            if m:
                token = m.group(1)
                provider["url"] = f"{public_base}/cma-provider/{token}"
                provider["interval"] = 300
                provider["path"] = f"./cma_traffic_{name}.yaml"
                changed = True
    return data, changed

if provider_src_dir.exists():
    for src in provider_src_dir.iterdir():
        if src.is_file():
            fixed = add_info_node_to_provider(load_yaml(src))
            if fixed is not None:
                dump_yaml(provider_out_dir / src.name, fixed)

for src in profile_src_dir.iterdir():
    if not src.is_file():
        continue
    data = load_yaml(src)
    if not isinstance(data, dict):
        continue
    data, changed = rewrite_profile_provider_urls(data)
    if changed or "proxy-providers" in data:
        dump_yaml(profile_out_dir / src.name, data)
PY
    chmod 755 /var/lib /var/lib/v2a-traffic "$CMA_PROFILE_OUT_DIR" "$CMA_PROVIDER_OUT_DIR" 2>/dev/null || true
    chmod 644 "$CMA_PROFILE_OUT_DIR"/* "$CMA_PROVIDER_OUT_DIR"/* 2>/dev/null || true
  fi
fi

echo "IFACE=$IFACE"
echo "START_DATE=$START_DATE"
echo "HEADER=$USERINFO"
echo "USED=${USED_GB_SHOW}G / ${TOTAL_GB_SHOW}G"
echo "LEFT=${LEFT_GB_SHOW}G"
UPDATER

  chmod +x "$UPDATE_BIN"
}

patch_nginx() {
  local sub_conf
  sub_conf="$(detect_nginx_sub_conf)"
  [ -n "$sub_conf" ] || die "没有找到 v2ray-agent 订阅 Nginx 配置"

  green "==> Patch Nginx 配置：$sub_conf"
  cp -a "$sub_conf" "$sub_conf.bak.v2a-traffic.$(date +%F-%H%M%S)"

  export V2A_SUB_CONF="$sub_conf"
  python3 <<'PY'
from pathlib import Path
import os
import re

p = Path(os.environ["V2A_SUB_CONF"])
s = p.read_text()

if "xray_subscription_userinfo.conf" not in s:
    s, n = re.subn(
        r'(alias\s+/etc/v2ray-agent/subscribe/\$1/\$2;\s*)',
        r'\1        include /etc/nginx/snippets/xray_subscription_userinfo.conf;\n',
        s,
        count=1
    )
    if n == 0:
        raise SystemExit("没有找到 /s/ 订阅 alias，无法添加 header include")

blocks = ""

if "location ^~ /sr/" not in s:
    blocks += '''    location ^~ /sr/ {
        default_type 'text/plain; charset=utf-8';
        alias /var/lib/v2a-traffic/shadowrocket-sub/;
        add_header profile-update-interval "6" always;
    }

'''

if "location ^~ /cma/" not in s:
    blocks += '''    location ^~ /cma/ {
        default_type 'text/plain; charset=utf-8';
        alias /var/lib/v2a-traffic/cma-sub/;
        include /etc/nginx/snippets/xray_subscription_userinfo.conf;
    }

'''

if "location ^~ /cma-provider/" not in s:
    blocks += '''    location ^~ /cma-provider/ {
        default_type 'text/plain; charset=utf-8';
        alias /var/lib/v2a-traffic/cma-provider/;
    }

'''

if blocks:
    s, n = re.subn(
        r'(\n\s*location\s+~\s+\^/s/)',
        "\n" + blocks + r"\1",
        s,
        count=1
    )
    if n == 0:
        raise SystemExit("没有找到 /s/ location，无法插入 /sr/ /cma/ location")

p.write_text(s)
PY

  nginx -t
  systemctl reload nginx
}

write_cron() {
  cat >"$CRON_FILE" <<EOF
*/5 * * * * root $UPDATE_BIN >/dev/null 2>&1
EOF
  green "定时任务已写入：$CRON_FILE"
}

run_update() {
  [ -x "$UPDATE_BIN" ] || write_update_script
  "$UPDATE_BIN"
}

show_urls() {
  load_config
  echo
  blue "========== 订阅地址 =========="
  echo

  echo "Clash Verge / Clash Verge Rev："
  if [ -d /etc/v2ray-agent/subscribe/clashMetaProfiles ]; then
    for f in /etc/v2ray-agent/subscribe/clashMetaProfiles/*; do
      [ -f "$f" ] && echo "  ${PUBLIC_BASE}/s/clashMetaProfiles/$(basename "$f")"
    done
  fi

  echo
  echo "Shadowrocket / 小火箭："
  if [ "${ENABLE_SR:-1}" = "1" ] && [ -d /etc/v2ray-agent/subscribe/default ]; then
    for f in /etc/v2ray-agent/subscribe/default/*; do
      [ -f "$f" ] && echo "  ${PUBLIC_BASE}/sr/$(basename "$f")"
    done
  else
    echo "  未启用"
  fi

  echo
  echo "Clash Meta for Android："
  if [ "${ENABLE_CMA:-1}" = "1" ]; then
    if [ -d "$DATA_DIR/cma-sub" ]; then
      for f in "$DATA_DIR"/cma-sub/*; do
        [ -f "$f" ] && echo "  ${PUBLIC_BASE}/cma/$(basename "$f")"
      done
    fi
  else
    echo "  未启用"
  fi

  echo
  blue "========== 测试命令 =========="
  local first_clash
  first_clash="$(find /etc/v2ray-agent/subscribe/clashMetaProfiles -maxdepth 1 -type f 2>/dev/null | head -n 1 || true)"
  if [ -n "$first_clash" ]; then
    echo "curl -sI \"${PUBLIC_BASE}/s/clashMetaProfiles/$(basename "$first_clash")\" | tr -d '\\r' | grep -i subscription-userinfo"
  fi
  echo
}

install_flow() {
  need_root
  check_v2ray_agent
  install_deps

  local iface
  iface="$(detect_iface)"
  [ -n "$iface" ] || die "无法检测默认网卡"
  green "默认网卡：$iface"
  vnstat --add -i "$iface" 2>/dev/null || true
  systemctl restart vnstat >/dev/null 2>&1 || true

  load_config
  ask_config
  write_update_script
  patch_nginx
  run_update
  write_cron
  show_urls
  green "安装 / 更新完成。"
}

modify_config_flow() {
  need_root
  load_config
  ask_config
  write_update_script
  run_update
  show_urls
}

uninstall_flow() {
  need_root
  echo
  yellow "此操作会删除本工具生成的脚本、配置、定时任务和订阅缓存。"
  yellow "Nginx 配置已自动备份过，但不会自动回滚，避免误删你自己的配置。"
  read -rp "确认卸载？[y/N]: " yn
  case "${yn:-N}" in
    y|Y|yes|YES)
      rm -f "$UPDATE_BIN" "$MANAGER_BIN" "$CRON_FILE"
      rm -rf "$CONFIG_DIR" "$DATA_DIR"
      rm -f "$HEADER_FILE"
      systemctl reload nginx >/dev/null 2>&1 || true
      green "已卸载。若要完全清理 Nginx location，请手动恢复 /etc/nginx/conf.d/subscribe.conf 的 .bak 备份。"
      ;;
    *) echo "已取消。" ;;
  esac
}

install_manager_copy() {
  if [ "${BASH_SOURCE[0]}" != "$MANAGER_BIN" ]; then
    cp -f "${BASH_SOURCE[0]}" "$MANAGER_BIN" 2>/dev/null || true
    chmod +x "$MANAGER_BIN" 2>/dev/null || true
  fi
}

menu() {
  while true; do
    echo
    blue "========== v2a-traffic 管理菜单 =========="
    echo "1) 安装 / 更新流量订阅显示"
    echo "2) 修改套餐流量参数"
    echo "3) 立即重新生成订阅"
    echo "4) 查看当前订阅地址"
    echo "5) 卸载本工具"
    echo "0) 退出"
    echo
    read -rp "请选择 [1-5/0]: " choice
    case "$choice" in
      1) install_flow; pause ;;
      2) modify_config_flow; pause ;;
      3) run_update; show_urls; pause ;;
      4) show_urls; pause ;;
      5) uninstall_flow; pause ;;
      0) exit 0 ;;
      *) red "无效选择" ;;
    esac
  done
}

main() {
  need_root
  install_manager_copy

  if [ ! -f "$CONFIG_FILE" ]; then
    install_flow
  else
    menu
  fi
}

main "$@"
