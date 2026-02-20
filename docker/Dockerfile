# OpenClaw Dockerfile
# 基于 Node.js 22 镜像

FROM node:22-bookworm-slim

# 构建模式参数: development 或 production
# development: 开发模式，包含更多调试工具和完整配置挂载
# production: 生产模式，最小化镜像，仅包含必需配置
ARG BUILD_MODE=production

# 标签
LABEL maintainer="OpenClaw Team"
LABEL description="OpenClaw - Personal AI Assistant"
LABEL build_mode="${BUILD_MODE}"

# 环境变量 - 最小化信息泄露
ENV NODE_ENV=production \
    OPENCLAW_VERSION=latest \
    DEBIAN_FRONTEND=noninteractive \
    # 禁用 Node.js 远程调试
    NODE_OPTIONS="--no-warnings" \
    # 设置时区
    TZ=UTC

# 创建非 root 用户和组 (如果不存在)
RUN (groupadd --gid 1000 node || true) && \
    (id -u node &>/dev/null || useradd --uid 1000 --gid node --shell /bin/false --create-home node)

# 安装系统依赖 - 根据构建模式调整
# production: 最小化安装
# development: 包含额外调试工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        dumb-init \
        git \
        $([ "$BUILD_MODE" = "development" ] && echo "vim nano procps htop net-tools") \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 设置工作目录
WORKDIR /home/node

# 创建必要目录并设置权限
# 注意: 根据构建模式创建不同的目录结构
RUN mkdir -p /home/node/.openclaw/workspace \
    /home/node/.openclaw/logs \
    /home/node/.openclaw/canvas \
    /home/node/.openclaw/cron \
    /home/node/openclaw_input \
    /home/node/.openclaw/secrets \
    /home/node/.openclaw/agents/main/agent \
    && chown -R node:node /home/node

# 开发模式: 创建临时配置目录用于文件复制
RUN if [ "$BUILD_MODE" = "production" ]; then \
        mkdir -p /tmp/openclaw_config && \
        chown -R node:node /tmp/openclaw_config; \
    fi

# 安装 OpenClaw (需要 root 权限写入 /usr/local)
# 优先使用官方源，在美国地区优先使用 registry.npmjs.org
RUN npm config set prefix /usr/local && \
    npm config set registry https://registry.npmjs.org/ && \
    npm install -g openclaw@latest --prefer-offline --no-audit --progress=false || \
    npm config set registry https://registry.npmmirror.com/ && \
    npm install -g openclaw@latest --prefer-offline --no-audit --progress=false

# 切换到非 root 用户
USER node

# 验证 openclaw 命令可用
RUN command -v openclaw || { echo "ERROR: openclaw installation failed"; exit 1; }

# 设置 PATH 包含 npm 全局 bin 目录
ENV PATH=/usr/local/bin:$PATH

# 暴露端口
EXPOSE 18789

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

# 入口点 - 使用 dumb-init 正确处理信号
ENTRYPOINT ["dumb-init", "--"]

# 默认命令
CMD ["openclaw", "gateway", "--port", "18789"]
