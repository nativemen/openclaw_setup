#!/bin/bash
# OpenClaw Gateway 启动脚本 (安全增强版 - 支持 Docker Secrets)
# 使用方法: ./start_with_token.sh [--mode env|secrets]
# 优先从 Docker Secrets 读取,其次从环境变量,最后使用配置文件中的token

set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
ENV_FILE="$BUILD_DIR/runtime/env/.env"
SECRETS_DIR="$BUILD_DIR/runtime/secrets"

# 解析参数
MODE="auto"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        *)
            echo "未知选项: $1"
            echo "用法: $0 [--mode env|secrets]"
            exit 1
            ;;
    esac
done

# 安全函数: 生成随机token
generate_token() {
    openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1
}

# 检查是否使用 Docker Secrets
use_docker_secrets() {
    if [ "$MODE" = "secrets" ]; then
        return 0
    elif [ "$MODE" = "env" ]; then
        return 1
    fi

    # 自动检测: 优先使用 secrets
    [ -d "$SECRETS_DIR" ] && [ -f "$SECRETS_DIR/gateway_token" ]
}

# 从 Docker Secrets 读取 token
read_token_from_secrets() {
    if [ -f "$SECRETS_DIR/gateway_token" ]; then
        cat "$SECRETS_DIR/gateway_token" | tr -d '\n\r'
        return 0
    fi
    return 1
}

# 获取token的优先级: Docker Secrets > 环境变量 > .env文件 > 动态生成
get_token() {
    # 1. 首先检查 Docker Secrets
    if use_docker_secrets; then
        local secrets_token=$(read_token_from_secrets)
        if [ -n "$secrets_token" ]; then
            echo "$secrets_token"
            return
        fi
    fi

    # 2. 检查环境变量
    if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
        echo "$OPENCLAW_GATEWAY_TOKEN"
        return
    fi

    # 3. 检查.env文件
    if [ -f "$ENV_FILE" ]; then
        local env_token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
        if [ -n "$env_token" ] && [ "$env_token" != "your-gateway-token-here" ]; then
            echo "$env_token"
            return
        fi
    fi

    # 4. 生成新token
    echo "$(generate_token)"
}

# 加载环境变量
load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE" 2>/dev/null || true
        set +a
    fi
}

# 检查 Docker 环境
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: Docker 未安装${NC}"
        exit 1
    fi

    if ! docker ps &> /dev/null; then
        echo -e "${RED}错误: Docker 未运行${NC}"
        exit 1
    fi

    # 检查 docker compose 插件或 docker-compose
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        echo -e "${RED}错误: Docker Compose 未安装${NC}"
        exit 1
    fi
}

# 选择启动配置
select_compose_args() {
    if use_docker_secrets && [ -f "$SCRIPT_DIR/docker-compose.prod.yml" ]; then
        echo "-f $SCRIPT_DIR/docker-compose.yml -f $SCRIPT_DIR/docker-compose.prod.yml"
    else
        echo "-f $SCRIPT_DIR/docker-compose.yml"
    fi
}

# 主函数
main() {
    echo -e "${GREEN}OpenClaw Gateway 启动 (安全增强模式)${NC}"
    echo ""

    # 加载环境变量
    load_env

    # 获取token
    GATEWAY_TOKEN=$(get_token)

    # 检查 Docker
    check_docker

    # 确定使用的 compose 配置
    COMPOSE_ARGS=$(select_compose_args)
    if use_docker_secrets; then
        echo -e "${GREEN}使用模式: Docker Secrets (生产环境)${NC}"
        echo -e "${BLUE}  配置文件: docker-compose.yml + docker-compose.prod.yml${NC}"
    else
        echo -e "${YELLOW}使用模式: 环境变量 (开发/测试环境)${NC}"
        echo -e "${BLUE}  配置文件: docker-compose.yml${NC}"
    fi
    echo ""

    # 启动 Docker 容器
    cd "$(dirname "$0")/docker"
    $DOCKER_COMPOSE $COMPOSE_ARGS up -d

    # 等待服务启动
    sleep 3

    # 安全方式: 使用 Authorization Header 而不是 URL 参数
    echo -e "${GREEN}正在打开浏览器...${NC}"
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:18789/"
    elif command -v gnome-open &> /dev/null; then
        gnome-open "http://localhost:18789/"
    elif command -v open &> /dev/null; then
        open "http://localhost:18789/"
    else
        echo "请手动打开浏览器访问: http://localhost:18789/"
    fi

    echo ""
    echo "Token 已配置 (通过 Authorization Header 传递)"
    echo ""
    echo "安全提示:"
    echo "  - Token 不再通过 URL 参数传递"
    echo "  - 请在 Web UI 中输入 Token 或设置 Authorization Header"
    echo "  - Token: ${GATEWAY_TOKEN:0:16}...${GATEWAY_TOKEN: -8}"
    echo ""

    if use_docker_secrets; then
        echo "  - 使用 Docker Secrets 模式,更安全!"
    else
        echo "  - 建议使用 Docker Secrets 模式以提高安全性:"
        echo "    mkdir -p config/secrets"
        echo "    openssl rand -hex 32 > config/secrets/gateway_token"
        echo "    chmod 600 config/secrets/gateway_token"
    fi
    echo ""
    echo "推荐使用以下方式认证:"
    echo "  curl -H 'Authorization: Bearer ${GATEWAY_TOKEN}' http://localhost:18789/"
}

main "$@"
