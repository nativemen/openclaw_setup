#!/bin/bash

###############################################################################
# OpenClaw Gateway 停止脚本
###############################################################################

# 严格模式
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/docker"

# 检测 Docker Compose 版本并设置命令
detect_docker_compose() {
    if docker compose version &> /dev/null 2>&1; then
        # Docker Compose V2
        echo "docker compose"
    elif command -v docker-compose &> /dev/null; then
        # Docker Compose V1
        echo "docker-compose"
    else
        echo -e "${RED}错误: Docker Compose 未安装${NC}"
        exit 1
    fi
}

DOCKER_COMPOSE=$(detect_docker_compose)

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}停止 OpenClaw Gateway...${NC}"

cd "$DOCKER_DIR"

# 停止容器
$DOCKER_COMPOSE down

echo -e "${GREEN}✓ OpenClaw Gateway 已停止${NC}"
