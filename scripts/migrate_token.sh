#!/bin/bash

###############################################################################
# OpenClaw Token 迁移脚本
# 将 Token 从环境变量模式迁移到 Docker Secrets 模式
###############################################################################

set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
ENV_FILE="$BUILD_DIR/runtime/env/.env"
SECRETS_DIR="$BUILD_DIR/runtime/secrets"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  OpenClaw Token 迁移工具${NC}"
echo -e "${BLUE}  环境变量 → Docker Secrets${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查当前模式
check_current_mode() {
    if [ -d "$SECRETS_DIR" ] && [ -f "$SECRETS_DIR/gateway_token" ]; then
        echo -e "${GREEN}当前模式: Docker Secrets${NC}"
        return 0
    else
        echo -e "${YELLOW}当前模式: 环境变量${NC}"
        return 1
    fi
}

# 检查环境变量文件中的 Token
check_env_token() {
    if [ -f "$ENV_FILE" ]; then
        local token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
        if [ -n "$token" ] && [ "$token" != "your-gateway-token-here" ]; then
            echo "$token"
            return 0
        fi
    fi
    return 1
}

# 创建 Docker Secrets 目录
create_secrets_dir() {
    if [ ! -d "$SECRETS_DIR" ]; then
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        echo -e "${GREEN}✓ 已创建 secrets 目录: $SECRETS_DIR${NC}"
    else
        chmod 700 "$SECRETS_DIR" 2>/dev/null || true
    fi
}

# 迁移 Token
migrate_token() {
    local env_token=""

    # 获取环境变量中的 Token
    env_token=$(check_env_token)

    if [ -z "$env_token" ]; then
        echo -e "${RED}错误: 未找到有效的 Token${NC}"
        echo ""
        echo "请先运行启动脚本配置 Token:"
        echo "  ./scripts/start_gateway.sh"
        exit 1
    fi

    echo -e "${YELLOW}发现现有 Token: ${env_token:0:16}...${env_token: -8}${NC}"
    echo ""

    # 备份当前 .env 文件
    if [ -f "$ENV_FILE" ]; then
        local backup_file="$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENV_FILE" "$backup_file"
        echo -e "${YELLOW}✓ 已备份 .env 文件到: $backup_file${NC}"
    fi

    # 创建 secrets 目录
    create_secrets_dir

    # 写入 secrets 文件
    echo -n "$env_token" > "$SECRETS_DIR/gateway_token"
    chmod 600 "$SECRETS_DIR/gateway_token"

    echo -e "${GREEN}✓ Token 已迁移到 Docker Secrets${NC}"
    echo ""

    # 可选：更新 .env 文件移除 Token
    if [ -f "$ENV_FILE" ]; then
        read -p "是否从 .env 文件中移除 Token? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 移除 Token 行（保留其他配置）
            sed -i '/^OPENCLAW_GATEWAY_TOKEN=/d' "$ENV_FILE"
            echo -e "${GREEN}✓ 已从 .env 文件中移除 Token${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}迁移完成!${NC}"
    echo ""
    echo "后续步骤:"
    echo "  1. 使用 Docker Secrets 模式启动:"
    echo "     ./scripts/start_with_token.sh --mode secrets"
    echo ""
    echo "  2. 或更新 docker-compose.yml 使用 secrets 配置"
    echo ""
}

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示帮助信息"
    echo "  -m, --migrate       执行迁移 (默认)"
    echo "  -c, --check         检查当前模式"
    echo "  -r, --rollback      回滚到环境变量模式"
    echo ""
    echo "说明:"
    echo "  此脚本将 Token 从环境变量模式迁移到 Docker Secrets 模式"
    echo "  Docker Secrets 更加安全,Token 不会出现在容器环境变量中"
    echo ""
}

# 回滚到环境变量模式
rollback() {
    if [ ! -f "$SECRETS_DIR/gateway_token" ]; then
        echo -e "${RED}错误: Docker Secrets 模式未配置${NC}"
        exit 1
    fi

    # 读取 secrets 中的 Token
    local token=$(cat "$SECRETS_DIR/gateway_token" | tr -d '\n\r')

    echo -e "${YELLOW}将从 Docker Secrets 回滚到环境变量模式...${NC}"
    echo ""

    # 确保 .env 文件存在
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
    fi

    # 备份当前配置
    local backup_file="$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$ENV_FILE" "$backup_file"

    # 更新或添加 Token
    if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$token|" "$ENV_FILE"
    else
        echo "OPENCLAW_GATEWAY_TOKEN=$token" >> "$ENV_FILE"
    fi

    echo -e "${GREEN}✓ Token 已回滚到环境变量${NC}"
    echo ""
    echo "备份文件: $backup_file"
}

# 主函数
main() {
    local action="migrate"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -m|--migrate)
                action="migrate"
                shift
                ;;
            -c|--check)
                action="check"
                shift
                ;;
            -r|--rollback)
                action="rollback"
                shift
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    # 执行操作
    case "$action" in
        check)
            check_current_mode
            ;;
        migrate)
            check_current_mode && exit 0
            migrate_token
            ;;
        rollback)
            rollback
            ;;
    esac
}

main "$@"
