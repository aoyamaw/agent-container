#!/bin/bash
set -euo pipefail

# 每次容器启动时根据环境变量自动刷新 /etc/environment，确保 Remote-SSH 非交互会话也能拿到完整 PATH 与代理
BASE_PATH="/home/agent/.local/share/fnm:/home/agent/.local/share/fnm/aliases/default/bin:/home/agent/.local/share/pnpm/bin:/home/agent/.local/share/pnpm:/home/agent/go/bin:/usr/local/go/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

{
  echo "PATH=\"${BASE_PATH}\""
  if [ "${RUNTIME_PROXY:-false}" = "true" ]; then
    PROXY_IP="${PROXY_IP:-192.168.3.110}"
    PROXY_PORT="${PROXY_PORT:-7890}"
    if [ -n "${PROXY_USER:-}" ] && [ -n "${PROXY_PASS:-}" ]; then
      PROXY_AUTH="${PROXY_USER}:${PROXY_PASS}@"
    else
      PROXY_AUTH=""
    fi
    HTTP_URL="http://${PROXY_AUTH}${PROXY_IP}:${PROXY_PORT}"
    SOCKS_URL="socks5h://${PROXY_AUTH}${PROXY_IP}:${PROXY_PORT}"
    NO_P="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.svc,.cluster.local"
    echo "http_proxy=\"${HTTP_URL}\""
    echo "https_proxy=\"${HTTP_URL}\""
    echo "all_proxy=\"${SOCKS_URL}\""
    echo "no_proxy=\"${NO_P}\""
    echo "HTTP_PROXY=\"${HTTP_URL}\""
    echo "HTTPS_PROXY=\"${HTTP_URL}\""
    echo "ALL_PROXY=\"${SOCKS_URL}\""
    echo "NO_PROXY=\"${NO_P}\""
  fi
} | sudo tee /etc/environment >/dev/null

sudo /usr/sbin/sshd
exec sleep infinity
