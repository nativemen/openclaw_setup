#!/bin/bash
###############################################################################
# OpenClaw Gateway Token Mismatch Fix Script
# Fixes "disconnected (1008): unauthorized: device token mismatch" error
#
# This script helps diagnose and fix WebSocket authentication failures
# caused by token mismatches between the gateway and browser client.
###############################################################################

set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
CONFIG_DIR="$PROJECT_ROOT/config"
ENV_FILE="$BUILD_DIR/runtime/env/.env"
SECRETS_FILE="$BUILD_DIR/runtime/secrets/gateway_token"
DOCKER_ENV_FILE="$BUILD_DIR/docker/.env"

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示帮助信息"
    echo "  -c, --check         检查当前 token 状态 (默认)"
    echo "  -r, --regenerate    重新生成 token 并同步到所有位置"
    echo "  -s, --sync          同步 .env 和 secrets 文件的 token"
    echo "  -f, --fix           完整修复: 重新生成 token + 显示清理指南"
    echo ""
    echo "示例:"
    echo "  $0 --check          # 检查当前 token 状态"
    echo "  $0 --regenerate     # 重新生成新 token"
    echo "  $0 --fix            # 完整修复流程"
    echo ""
}

# 生成新的随机token
generate_token() {
    openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1
}

# 从 .env 文件读取 token
read_token_from_env() {
    if [ -f "$ENV_FILE" ]; then
        grep "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo ""
    else
        echo ""
    fi
}

# 从 secrets 文件读取 token
read_token_from_secrets() {
    if [ -f "$SECRETS_FILE" ]; then
        cat "$SECRETS_FILE" | tr -d '\n\r' || echo ""
    else
        echo ""
    fi
}

# 从 docker/.env 文件读取 token
read_token_from_docker_env() {
    if [ -f "$DOCKER_ENV_FILE" ]; then
        grep "^OPENCLAW_GATEWAY_TOKEN=" "$DOCKER_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo ""
    else
        echo ""
    fi
}

# 显示 token (掩码)
mask_token() {
    local token="$1"
    if [ -n "$token" ] && [ ${#token} -gt 24 ]; then
        echo "${token:0:16}...${token: -8}"
    elif [ -n "$token" ]; then
        echo "${token:0:8}...${token: -4}"
    else
        echo "(空)"
    fi
}

# 检查 token 状态
check_token_status() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Token 状态检查${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    local env_token=""
    local secrets_token=""
    local docker_env_token=""
    local env_exists=false
    local secrets_exists=false
    local docker_env_exists=false

    # 检查 .env 文件
    if [ -f "$ENV_FILE" ]; then
        env_exists=true
        env_token=$(read_token_from_env)
        echo -e "${GREEN}✓ .env 文件存在${NC}"
        echo "  位置: $ENV_FILE"
        if [ -n "$env_token" ]; then
            echo "  Token: $(mask_token "$env_token")"
        else
            echo -e "  Token: ${YELLOW}(未设置)${NC}"
        fi
    else
        echo -e "${RED}✗ .env 文件不存在${NC}"
        echo "  位置: $ENV_FILE"
    fi
    echo ""

    # 检查 secrets 文件
    if [ -f "$SECRETS_FILE" ]; then
        secrets_exists=true
        secrets_token=$(read_token_from_secrets)
        echo -e "${GREEN}✓ Secrets 文件存在${NC}"
        echo "  位置: $SECRETS_FILE"
        if [ -n "$secrets_token" ]; then
            echo "  Token: $(mask_token "$secrets_token")"
        else
            echo -e "  Token: ${YELLOW}(空文件)${NC}"
        fi
    else
        echo -e "${RED}✗ Secrets 文件不存在${NC}"
        echo "  位置: $SECRETS_FILE"
    fi
    echo ""

    # 检查 docker/.env 文件
    if [ -f "$DOCKER_ENV_FILE" ]; then
        docker_env_exists=true
        docker_env_token=$(read_token_from_docker_env)
        echo -e "${GREEN}✓ docker/.env 文件存在${NC}"
        echo "  位置: $DOCKER_ENV_FILE"
        if [ -n "$docker_env_token" ]; then
            echo "  Token: $(mask_token "$docker_env_token")"
        else
            echo -e "  Token: ${YELLOW}(未设置)${NC}"
        fi
    else
        echo -e "${YELLOW}! docker/.env 文件不存在${NC}"
        echo "  位置: $DOCKER_ENV_FILE"
    fi
    echo ""

    # 比较 token
    echo -e "${BLUE}Token 一致性检查:${NC}"
    local all_tokens=()
    [ -n "$env_token" ] && all_tokens+=("$env_token")
    [ -n "$secrets_token" ] && all_tokens+=("$secrets_token")
    [ -n "$docker_env_token" ] && all_tokens+=("$docker_env_token")

    if [ ${#all_tokens[@]} -eq 0 ]; then
        echo -e "${RED}✗ 未找到任何 token 配置${NC}"
        echo "  建议运行: $0 --regenerate"
    else
        # 检查所有 token 是否一致
        local all_match=true
        local first_token="${all_tokens[0]}"
        for token in "${all_tokens[@]}"; do
            if [ "$token" != "$first_token" ]; then
                all_match=false
                break
            fi
        done

        if [ "$all_match" = true ]; then
            echo -e "${GREEN}✓ 所有 Token 一致${NC}"
            echo "  所有配置文件中的 token 匹配"
        else
            echo -e "${RED}✗ Token 不匹配!${NC}"
            [ -n "$env_token" ] && echo "  build/runtime/env/.env: $(mask_token "$env_token")"
            [ -n "$secrets_token" ] && echo "  build/runtime/secrets/gateway_token: $(mask_token "$secrets_token")"
            [ -n "$docker_env_token" ] && echo "  build/docker/.env: $(mask_token "$docker_env_token")"
            echo ""
            echo -e "${YELLOW}这会导致 WebSocket 认证失败 (错误 1008)${NC}"
            echo "建议运行: $0 --sync 同步 token"
        fi
    fi
    echo ""
}

# 同步 token
sync_tokens() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  同步 Token${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    local env_token=$(read_token_from_env)
    local secrets_token=$(read_token_from_secrets)
    local docker_env_token=$(read_token_from_docker_env)

    # 确定使用哪个 token 作为源 (优先级: secrets > build/runtime/env/.env > docker/.env)
    local source_token=""
    local source_name=""

    if [ -n "$secrets_token" ]; then
        source_token="$secrets_token"
        source_name="secrets"
    elif [ -n "$env_token" ]; then
        source_token="$env_token"
        source_name="build/runtime/env/.env"
    elif [ -n "$docker_env_token" ]; then
        source_token="$docker_env_token"
        source_name="docker/.env"
    else
        echo -e "${RED}✗ 没有找到可用的 token 作为同步源${NC}"
        echo "  建议运行: $0 --regenerate 生成新 token"
        return 1
    fi

    echo "使用 $source_name 中的 token 作为源"
    echo "Token: $(mask_token "$source_token")"
    echo ""

    # 同步到 build/runtime/env/.env
    if [ "$source_name" != "build/runtime/env/.env" ] || [ -z "$env_token" ]; then
        echo "同步到 build/runtime/env/.env 文件..."
        mkdir -p "$(dirname "$ENV_FILE")"
        if [ -f "$ENV_FILE" ]; then
            if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null; then
                sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$source_token|" "$ENV_FILE"
            else
                echo "OPENCLAW_GATEWAY_TOKEN=$source_token" >> "$ENV_FILE"
            fi
        else
            echo "OPENCLAW_GATEWAY_TOKEN=$source_token" > "$ENV_FILE"
        fi
        echo -e "${GREEN}✓ 已更新 build/runtime/env/.env 文件${NC}"
    fi

    # 同步到 secrets
    if [ "$source_name" != "secrets" ] || [ -z "$secrets_token" ]; then
        echo "同步到 secrets 文件..."
        mkdir -p "$(dirname "$SECRETS_FILE")"
        echo -n "$source_token" > "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"
        echo -e "${GREEN}✓ 已更新 build/runtime/secrets/gateway_token 文件${NC}"
    fi

    # 同步到 docker/.env
    if [ "$source_name" != "docker/.env" ] || [ -z "$docker_env_token" ]; then
        echo "同步到 docker/.env 文件..."
        mkdir -p "$(dirname "$DOCKER_ENV_FILE")"
        if [ -f "$DOCKER_ENV_FILE" ]; then
            if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$DOCKER_ENV_FILE" 2>/dev/null; then
                sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$source_token|" "$DOCKER_ENV_FILE"
            else
                echo "OPENCLAW_GATEWAY_TOKEN=$source_token" >> "$DOCKER_ENV_FILE"
            fi
        else
            echo "OPENCLAW_GATEWAY_TOKEN=$source_token" > "$DOCKER_ENV_FILE"
        fi
        echo -e "${GREEN}✓ 已更新 build/docker/.env 文件${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ Token 同步完成${NC}"
    echo ""
}

# 重新生成 token
regenerate_token() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  重新生成 Token${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    # 备份现有配置
    local backup_dir="$CONFIG_DIR/backups"
    mkdir -p "$backup_dir"

    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "$backup_dir/.env.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}已备份 .env 文件${NC}"
    fi

    if [ -f "$SECRETS_FILE" ]; then
        cp "$SECRETS_FILE" "$backup_dir/gateway_token.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}已备份 secrets 文件${NC}"
    fi

    # 生成新 token
    echo ""
    echo "生成新的 Gateway Token..."
    local new_token=$(generate_token)

    # 更新 .env
    mkdir -p "$(dirname "$ENV_FILE")"
    if [ -f "$ENV_FILE" ]; then
        if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null; then
            sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$new_token|" "$ENV_FILE"
        else
            echo "OPENCLAW_GATEWAY_TOKEN=$new_token" >> "$ENV_FILE"
        fi
    else
        echo "OPENCLAW_GATEWAY_TOKEN=$new_token" > "$ENV_FILE"
    fi

    # 更新 secrets
    mkdir -p "$(dirname "$SECRETS_FILE")"
    echo -n "$new_token" > "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"

    echo ""
    echo -e "${GREEN}✓ 新 Token 已生成并同步${NC}"
    echo "  Token: $(mask_token "$new_token")"
    echo ""
    echo -e "${YELLOW}重要: 需要重启 Gateway 使新 Token 生效${NC}"
    echo "  运行: cd docker && docker compose restart"
    echo ""
}

# 显示浏览器清理指南
show_browser_cleanup_guide() {
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  浏览器缓存清理指南${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    echo -e "${YELLOW}为什么需要清理浏览器缓存？${NC}"
    echo "  WebSocket 认证失败 (错误 1008) 通常是因为浏览器"
    echo "  缓存了旧的 token，而网关使用了新的 token。"
    echo ""
    echo -e "${BLUE}清理步骤:${NC}"
    echo ""
    echo "1. 打开浏览器开发者工具 (F12)"
    echo "2. 切换到 Application (应用) 标签"
    echo "3. 在左侧选择 Local Storage -> http://localhost:18789"
    echo "4. 删除所有与 'token' 相关的键值"
    echo "   - 通常键名为: openclaw_token, gateway_token, device_token 等"
    echo ""
    echo -e "${BLUE}或者使用控制台命令快速清理:${NC}"
    echo "  localStorage.clear();"
    echo "  sessionStorage.clear();"
    echo ""
    echo -e "${BLUE}快捷方式 (在浏览器控制台执行):${NC}"
    cat << 'EOF'

// 清理 OpenClaw 相关存储
Object.keys(localStorage).forEach(key => {
    if (key.toLowerCase().includes('token') ||
        key.toLowerCase().includes('openclaw') ||
        key.toLowerCase().includes('gateway')) {
        console.log('删除:', key);
        localStorage.removeItem(key);
    }
});
sessionStorage.clear();
console.log('✓ 已清理 token 缓存，请刷新页面');

EOF
    echo ""
    echo -e "${GREEN}清理完成后，刷新页面即可重新连接${NC}"
    echo ""
}

# 完整修复流程
full_fix() {
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  开始完整修复流程${NC}"
    echo -e "${RED}============================================${NC}"
    echo ""

    # 1. 检查当前状态
    check_token_status
    echo ""

    # 2. 重新生成 token
    read -p "是否重新生成 token? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        regenerate_token
        echo ""
    else
        echo -e "${YELLOW}跳过 token 重新生成${NC}"
        echo ""
    fi

    # 3. 显示浏览器清理指南
    show_browser_cleanup_guide

    # 4. 显示后续步骤
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  后续步骤${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo "1. 重启 Gateway 服务:"
    echo "   cd docker && docker compose restart"
    echo ""
    echo "2. 清理浏览器缓存 (按上述指南)"
    echo ""
    echo "3. 刷新 OpenClaw Control UI 页面"
    echo "   http://localhost:18789"
    echo ""
    echo "4. 验证连接:"
    echo "   - 检查 WebSocket 是否成功连接"
    echo "   - 确认不再出现 'device token mismatch' 错误"
    echo ""
    echo -e "${GREEN}修复完成!${NC}"
}

# 主函数
main() {
    local action="check"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                action="check"
                shift
                ;;
            -r|--regenerate)
                action="regenerate"
                shift
                ;;
            -s|--sync)
                action="sync"
                shift
                ;;
            -f|--fix)
                action="fix"
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
            check_token_status
            ;;
        regenerate)
            regenerate_token
            show_browser_cleanup_guide
            ;;
        sync)
            sync_tokens
            show_browser_cleanup_guide
            ;;
        fix)
            full_fix
            ;;
    esac
}

main "$@"
