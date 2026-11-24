function proxyenv() {
  local proxyfile="$HOME/set-proxy.sh"

  if [[ ! -f "$proxyfile" ]]; then
    echo "proxyenv: set-proxy.sh not found: $proxyfile" >&2
    return 1
  fi

  bash -c '
    set -a
    source "$1"
    set +a
    exec "${@:2}"
  ' _ "$proxyfile" "$@"
}

# 提前配置 pnpm 与 Go 全局命令目录
export PNPM_HOME="$HOME/.local/share/pnpm"
export GOPATH="${GOPATH:-$HOME/go}"
export GOROOT="${GOROOT:-/usr/local/go}"
for _p in "$PNPM_HOME/bin" "$GOPATH/bin" "$GOROOT/bin"; do
  case ":$PATH:" in
    *":$_p:"*) ;;
    *) export PATH="$_p:$PATH" ;;
  esac
done
unset _p

# 容器内开启 RUNTIME_PROXY=true 时，自动静默加载内网代理（确保 tmux 里的 Polecat 自动联网且不拦截本地 Dolt）
if [[ "${RUNTIME_PROXY:-false}" == "true" && -z "${http_proxy:-}" && -f "$HOME/set-proxy.sh" ]]; then
  source "$HOME/set-proxy.sh" >/dev/null
fi

alias codex-api='CODEX_HOME="$HOME/.codex-api" proxyenv codex'

# 一键自检 Gas Town、各 CLI 工具链与订阅隔离状态
function gt-check() {
  echo "=== Core Toolchain ==="
  for entry in "go:version" "dolt:version" "bd:version" "gt:--version" "tmux:-V" "git:--version" "node:--version" "pnpm:--version"; do
    local cmd="${entry%%:*}"
    local flag="${entry#*:}"
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "  %-8s: %s\n" "$cmd" "$("$cmd" "$flag" 2>&1 | head -n 1)"
    else
      printf "  %-8s: MISSING\n" "$cmd"
    fi
  done
  echo "=== Coding Agent CLIs ==="
  for cmd in codex pi agy claude; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "  %-8s: %s\n" "$cmd" "$("$cmd" --version 2>&1 | head -n 1)"
    else
      printf "  %-8s: MISSING\n" "$cmd"
    fi
  done
  echo "=== Subscription Safety Check ==="
  for key in OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY; do
    if [[ -n "${!key:-}" ]]; then
      echo "  [WARN] $key is set (may override subscription login!)"
    else
      echo "  [OK]   $key is unset"
    fi
  done
}
