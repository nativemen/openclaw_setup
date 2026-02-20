#!/bin/bash
###############################################################################
# OpenClaw Gateway Token 轮换脚本 (安全增强版)
# 支持 Docker Secrets 和环境变量两种模式
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

# 生成新的随机token
generate_token() {
    openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示帮助信息"
    echo "  -r, --rotate        轮换 token (默认)"
    echo "  -v, --validate      验证当前 token"
    echo "  -s, --show          显示当前 token (掩码后)"
    echo "  -m, --mode          指定存储模式: env|secrets (默认: env)"
    echo ""
    echo "示例:"
    echo "  $0 --rotate              # 轮换 token (环境变量模式)"
    echo "  $0 --rotate --mode secrets  # 轮换 token (Docker Secrets模式)"
    echo "  $0 --validate           # 验证 token"
    echo ""
}

# 检查 Docker Secrets 模式
use_docker_secrets() {
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

# 验证当前 token
validate_token() {
    local token=""

    # 优先从 Docker Secrets 读取
    if use_docker_secrets; then
        token=$(read_token_from_secrets)
        if [ -n "$token" ]; then
            echo -e "${GREEN}✓ Token 已配置 (Docker Secrets 模式)${NC}"
            echo "  Token: ${token:0:16}...${token: -8}"
            return 0
        fi
    fi

    # 回退到环境变量模式
    if [ -f "$ENV_FILE" ]; then
        token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
        if [ -n "$token" ] && [ "$token" != "your-gateway-token-here" ]; then
            echo -e "${GREEN}✓ Token 已配置 (环境变量模式)${NC}"
            echo "  Token: ${token:0:16}...${token: -8}"
            return 0
        fi
    fi

    echo -e "${RED}✗ Token 未配置或无效${NC}"
    return 1
}

# 轮换 token (环境变量模式)
rotate_token_env() {
    echo -e "${BLUE}开始轮换 Gateway Token (环境变量模式)...${NC}"
    echo ""

    # 备份当前配置
    if [ -f "$ENV_FILE" ]; then
        local backup_file="$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENV_FILE" "$backup_file"
        echo -e "${YELLOW}已备份当前配置到: $backup_file${NC}"
    fi

    # 确保 .env 文件存在
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
    fi

    # 生成新 token
    local new_token=$(generate_token)

    # 更新或添加 token
    if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$new_token|" "$ENV_FILE"
    else
        echo "OPENCLAW_GATEWAY_TOKEN=$new_token" >> "$ENV_FILE"
    fi

    echo ""
    echo -e "${GREEN}✓ Token 轮换完成!${NC}"
    echo ""
    echo "新 Token: ${new_token:0:16}...${new_token: -8}"
    echo ""
    echo -e "${YELLOW}请执行以下步骤使新 Token 生效:${NC}"
    echo "  1. 重启 Gateway: cd docker && docker compose restart"
    echo "  2. 更新客户端配置中的 token"
    echo ""
    echo "API 调用示例:"
    echo "  curl -H 'Authorization: Bearer $new_token' http://localhost:18789/"
    echo ""
    echo "安全建议:"
    echo "  - 旧 Token 仍然有效直到 Gateway 重启"
    echo "  - 建议在低峰期进行轮换"
    echo "  - 记录轮换时间以便审计"
    echo ""
    echo -e "${YELLOW}⚠️  重要: 轮换后需要清理浏览器缓存${NC}"
    echo "  浏览器可能缓存了旧 token，导致 WebSocket 连接失败 (错误 1008)"
    echo "  请运行以下命令清理缓存:"
    echo ""
    echo "    ./scripts/fix_token_mismatch.sh --fix"
    echo ""
    echo "  或手动清理:"
    echo "  1. 打开浏览器开发者工具 (F12)"
    echo "  2. 切换到 Application/Storage 标签"
    echo "  3. 清除 Local Storage 和 Session Storage"
    echo "  4. 刷新页面"
}

# 轮换 token (Docker Secrets 模式)
rotate_token_secrets() {
    echo -e "${BLUE}开始轮换 Gateway Token (Docker Secrets 模式)...${NC}"
    echo ""

    # 确保 secrets 目录存在
    if [ ! -d "$SECRETS_DIR" ]; then
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        echo -e "${YELLOW}已创建 secrets 目录: $SECRETS_DIR${NC}"
    fi

    # 备份当前 secrets
    if [ -f "$SECRETS_DIR/gateway_token" ]; then
        local backup_file="$SECRETS_DIR/gateway_token.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SECRETS_DIR/gateway_token" "$backup_file"
        echo -e "${YELLOW}已备份当前 secrets 到: $backup_file${NC}"
    fi

    # 生成新 token
    local new_token=$(generate_token)

    # 写入 secrets 文件 (严格权限)
    echo -n "$new_token" > "$SECRETS_DIR/gateway_token"
    chmod 600 "$SECRETS_DIR/gateway_token"

    echo ""
    echo -e "${GREEN}✓ Token 轮换完成 (Docker Secrets 模式)!${NC}"
    echo ""
    echo "新 Token: ${new_token:0:16}...${new_token: -8}"
    echo ""
    echo -e "${YELLOW}请执行以下步骤使新 Token 生效:${NC}"
    echo "  1. 重启 Gateway: cd docker && docker compose restart"
    echo "  2. 更新客户端配置中的 token"
    echo ""
    echo "API 调用示例:"
    echo "  curl -H 'Authorization: Bearer $new_token' http://localhost:18789/"
    echo ""
    echo "安全建议:"
    echo "  - 旧 Token 仍然有效直到 Gateway 重启"
    echo "  - Docker Secrets 模式更加安全，Token 不会出现在环境变量中"
    echo ""
    echo -e "${YELLOW}⚠️  重要: 轮换后需要清理浏览器缓存${NC}"
    echo "  浏览器可能缓存了旧 token，导致 WebSocket 连接失败 (错误 1008)"
    echo "  请运行以下命令清理缓存:"
    echo ""
    echo "    ./scripts/fix_token_mismatch.sh --fix"
    echo ""
    echo "  或手动清理:"
    echo "  1. 打开浏览器开发者工具 (F12)"
    echo "  2. 切换到 Application/Storage 标签"
    echo "  3. 清除 Local Storage 和 Session Storage"
    echo "  4. 刷新页面"
}

# 轮换 token (自动选择模式)
rotate_token() {
    local mode="${1:-auto}"

    if [ "$mode" = "secrets" ]; then
        rotate_token_secrets
    elif [ "$mode" = "env" ]; then
        rotate_token_env
    else
        # 自动选择: 优先使用 Docker Secrets
        if use_docker_secrets; then
            rotate_token_secrets
        else
            rotate_token_env
        fi
    fi
}

# 显示当前 token (掩码)
show_token() {
    # 优先从 Docker Secrets 读取
    if use_docker_secrets; then
        local token=$(read_token_from_secrets)
        if [ -n "$token" ]; then
            echo "当前 Token (Docker Secrets): ${token:0:16}...${token: -8}"
            return 0
        fi
    fi

    # 回退到环境变量模式
    if [ -f "$ENV_FILE" ]; then
        local token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
        if [ -n "$token" ] && [ "$token" != "your-gateway-token-here" ]; then
            echo "当前 Token (环境变量): ${token:0:16}...${token: -8}"
            return 0
        fi
    fi

    echo -e "${RED}未找到已配置的 Token${NC}"
    return 1
}

# 显示当前使用模式
show_mode() {
    if use_docker_secrets; then
        echo -e "${GREEN}当前模式: Docker Secrets${NC}"
    else
        echo -e "${YELLOW}当前模式: 环境变量${NC}"
    fi
}

# 主函数
main() {
    local action="rotate"
    local mode="auto"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -r|--rotate)
                action="rotate"
                shift
                ;;
            -v|--validate)
                action="validate"
                shift
                ;;
            -s|--show)
                action="show"
                shift
                ;;
            -m|--mode)
                mode="$2"
                shift 2
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
        rotate)
            rotate_token "$mode"
            ;;
        validate)
            show_mode
            echo ""
            validate_token
            ;;
        show)
            show_mode
            echo ""
            show_token
            ;;
    esac
}

main "$@"
