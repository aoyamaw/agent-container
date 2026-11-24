# Debian Trixie 精简基础镜像
FROM docker.io/library/debian:trixie-slim

# OCI 标准元数据
LABEL org.opencontainers.image.title="AI Agent Execution Environment (Gas Town)" \
      org.opencontainers.image.description="Container environment tailored for multi-agent coding workloads with Gas Town, Beads, Dolt, Codex, Pi, Claude Code, and Gemini CLI" \
      org.opencontainers.image.vendor="Local Engine" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    WORKSPACE_DIRD="/home/agent/workspace" \
    FNM_DIR="/home/agent/.local/share/fnm" \
    PNPM_HOME="/home/agent/.local/share/pnpm" \
    GOROOT="/usr/local/go" \
    GOPATH="/home/agent/go" \
    GOTOOLCHAIN="auto"

# 直接执行容器命令时也能使用默认 Node.js、pnpm、Go 与 Gas Town 全局命令
ENV PATH="${FNM_DIR}:${FNM_DIR}/aliases/default/bin:${PNPM_HOME}/bin:${PNPM_HOME}:${GOPATH}/bin:${GOROOT}/bin:/home/agent/.local/bin:${PATH}"

# 默认使用清华大学 Debian APT 镜像源
ARG USE_CHINA_APT_MIRROR=true

# 安装开发环境依赖；fnm 需要 curl/unzip，Codex 沙箱需要 bubblewrap，Gas Town/Beads 需要 tmux/sqlite3/libicu-dev/pkg-config
RUN if [ "$USE_CHINA_APT_MIRROR" = "true" ]; then \
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/debian.sources && \
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; \
    fi \
    && apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    ripgrep \
    tmux \
    sqlite3 \
    libicu-dev \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    bubblewrap \
    unzip \
    sudo \
    openssh-server \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建 sshd 运行所需目录
RUN mkdir -p /run/sshd

# 创建 UID 1000 的非 root 开发用户
RUN useradd -m -s /bin/bash -u 1000 agent

# 设置本地开发使用的默认密码
RUN echo 'agent:agent123' | chpasswd && \
    echo 'root:root123' | chpasswd

# 配置 agent 用户的无密码 sudo 权限
RUN echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent

# 将外部工具和脚本放入 agent 用户目录，并追加外部 bashrc 配置
# 确保非交互 SSH / 登录 shell 同样保留完整 PATH
RUN cat <<'EOF' > /etc/profile.d/agent-env.sh
export WORKSPACE_DIRD="/home/agent/workspace"
export FNM_DIR="/home/agent/.local/share/fnm"
export PNPM_HOME="/home/agent/.local/share/pnpm"
export GOROOT="/usr/local/go"
export GOPATH="/home/agent/go"
export GOTOOLCHAIN="auto"
export PATH="${FNM_DIR}:${FNM_DIR}/aliases/default/bin:${PNPM_HOME}/bin:${PNPM_HOME}:${GOPATH}/bin:${GOROOT}/bin:/home/agent/.local/bin:${PATH}"
EOF

# 预创建持久化卷挂载目录，避免 Named Volume 首次挂载属主变成 root
RUN mkdir -p /home/agent/.codex /home/agent/.claude /home/agent/.gemini /home/agent/.pi /home/agent/gt /home/agent/.local/share/pnpm/store /home/agent/.local/bin \
    && chown -R agent:agent /home/agent

COPY --chown=agent:agent home/ /home/agent/
RUN chmod +x /home/agent/.local/bin/w
COPY bashrc.sh /tmp/agent-bashrc
RUN printf '\n' >> /home/agent/.bashrc \
    && cat /tmp/agent-bashrc >> /home/agent/.bashrc \
    && rm /tmp/agent-bashrc \
    && chown agent:agent /home/agent/.bashrc

# 切换至非 root 用户并设置工作目录
USER agent
WORKDIR ${WORKSPACE_DIRD}

# 构建期代理配置（仅用于无国内镜像的少量下载，优先走国内直连镜像节省代理流量）
ARG USE_PROXY=true
ARG PROXY_IP=192.168.3.110
ARG PROXY_PORT=7890
ARG PROXY_USER=
ARG PROXY_PASS=

ARG USE_CHINA_NPM_MIRROR=true
ARG NODE_VERSION=26.8.2

# 通过 fnm 安装固定版本的 Node.js（Node.js 二进制优先走 npmmirror 国内镜像直连）
RUN set -eu; \
    mkdir -p "$PNPM_HOME/bin"; \
    if [ "$USE_PROXY" = "true" ]; then \
        export PROXY_IP PROXY_PORT PROXY_USER PROXY_PASS; \
        . "$HOME/set-proxy.sh"; \
    fi; \
    curl -fsSL https://fnm.vercel.app/install -o /tmp/fnm-install.sh; \
    SHELL=/bin/bash bash /tmp/fnm-install.sh --install-dir "$FNM_DIR"; \
    rm /tmp/fnm-install.sh; \
    if [ "$USE_CHINA_NPM_MIRROR" = "true" ]; then \
        . "$HOME/unset-proxy.sh"; \
        export FNM_NODE_DIST_MIRROR="https://npmmirror.com/mirrors/node"; \
    fi; \
    eval "$(fnm env --shell bash)"; \
    fnm install "$NODE_VERSION" --use; \
    fnm default "$NODE_VERSION"

ARG PNPM_VERSION=12.4.1

# 安装 Corepack 和固定版本 pnpm，并按需配置 npm 国内镜像
RUN set -eu; \
    eval "$(fnm env --shell bash)"; \
    if [ "$USE_CHINA_NPM_MIRROR" = "true" ]; then \
        npm config set registry https://registry.npmmirror.com; \
        export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com; \
    fi; \
    npm install --global corepack@latest; \
    corepack enable pnpm; \
    corepack prepare "pnpm@$PNPM_VERSION" --activate; \
    if [ "$USE_CHINA_NPM_MIRROR" = "true" ]; then \
        pnpm config set registry https://registry.npmmirror.com; \
    fi

ARG CODEX_VERSION=0.154.0
ARG PI_VERSION=0.85.1
ARG CLAUDE_CODE_VERSION=latest
ARG GEMINI_CLI_VERSION=latest

# 安装主流 Coding Agent CLI（Codex / Pi / Claude Code / Gemini CLI）
RUN set -eu; \
    eval "$(fnm env --shell bash)"; \
    pnpm install --global "@openai/codex@$CODEX_VERSION"; \
    pnpm add --global --ignore-scripts "@earendil-works/pi-coding-agent@$PI_VERSION"; \
    pnpm install --global "@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION"; \
    pnpm install --global "@google/gemini-cli@$GEMINI_CLI_VERSION"

ARG GO_VERSION=1.26.0
ARG USE_CHINA_GO_PROXY=true
ARG BEADS_VERSION=latest
ARG GASTOWN_VERSION=latest

# 安装 Go、Dolt、Beads (bd) 与 Gas Town (gt)（Go 与 Go 模块优先走国内直连镜像，仅 Dolt 按需走代理）
RUN set -eu; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "$USE_CHINA_GO_PROXY" = "true" ]; then \
        GO_URL="https://mirrors.aliyun.com/golang/go${GO_VERSION}.linux-${ARCH}.tar.gz"; \
        export GOPROXY="https://goproxy.cn,direct"; \
    else \
        GO_URL="https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz"; \
    fi; \
    curl -fsSL "$GO_URL" -o /tmp/go.tar.gz; \
    sudo rm -rf /usr/local/go; \
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz; \
    rm /tmp/go.tar.gz; \
    mkdir -p "$GOPATH/bin"; \
    CGO_ENABLED=1 go install "github.com/steveyegge/beads/cmd/bd@${BEADS_VERSION}"; \
    CGO_ENABLED=1 go install "github.com/steveyegge/gastown/cmd/gt@${GASTOWN_VERSION}"; \
    if [ "$USE_PROXY" = "true" ]; then \
        export PROXY_IP PROXY_PORT PROXY_USER PROXY_PASS; \
        . "$HOME/set-proxy.sh"; \
    fi; \
    curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | sudo -E bash

# 默认启动 Bash
CMD ["/bin/bash"]
