#!/bin/bash

###############################################################################
# OpenClaw 安全检查脚本
# 检查当前部署的安全配置状态
###############################################################################

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
SECRETS_DIR="$PROJECT_ROOT/build/runtime/secrets"
ENV_FILE="$PROJECT_ROOT/build/runtime/env/.env"

# 统计结果
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNING_CHECKS=0
FAILED_CHECKS=0

# 检查函数
check() {
    local name="$1"
    local status="$2"
    local message="$3"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    case "$status" in
        pass)
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            echo -e "  ${GREEN}✓${NC} $name"
            ;;
        warn)
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            echo -e "  ${YELLOW}⚠${NC} $name"
            ;;
        fail)
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            echo -e "  ${RED}✗${NC} $name"
            ;;
    esac

    if [ -n "$message" ]; then
        echo -e "      $message"
    fi
}

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  OpenClaw 安全检查${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 1. Token 存储模式检查
echo -e "${YELLOW}[1] Token 存储模式${NC}"
if [ -d "$SECRETS_DIR" ] && [ -f "$SECRETS_DIR/gateway_token" ]; then
    check "Docker Secrets 模式" "pass" "Token 存储在 $SECRETS_DIR/gateway_token"
else
    check "Docker Secrets 模式" "warn" "未配置 Docker Secrets，使用环境变量模式"
    check "环境变量模式" "warn" "Token 存储在 $ENV_FILE"
fi
echo ""

# 2. .env 文件权限检查
echo -e "${YELLOW}[2] 文件权限${NC}"
if [ -f "$ENV_FILE" ]; then
    env_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %Lp "$ENV_FILE" 2>/dev/null || echo "unknown")
    if [ "$env_perms" = "600" ] || [ "$env_perms" = "400" ]; then
        check ".env 文件权限" "pass" "权限: $env_perms (安全)"
    else
        check ".env 文件权限" "warn" "权限: $env_perms (建议改为 600)"
    fi
else
    check ".env 文件" "warn" "文件不存在"
fi

if [ -d "$SECRETS_DIR" ]; then
    secrets_perms=$(stat -c %a "$SECRETS_DIR" 2>/dev/null || stat -f %Lp "$SECRETS_DIR" 2>/dev/null || echo "unknown")
    if [ "$secrets_perms" = "700" ]; then
        check "secrets 目录权限" "pass" "权限: $secrets_perms (安全)"
    else
        check "secrets 目录权限" "warn" "权限: $secrets_perms (建议改为 700)"
    fi
fi
echo ""

# 3. .gitignore 检查
echo -e "${YELLOW}[3] Git 忽略配置${NC}"
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    if grep -q "build/runtime/env/.env" "$PROJECT_ROOT/.gitignore"; then
        check ".env 在 .gitignore 中" "pass"
    else
        check ".env 在 .gitignore 中" "warn" "建议添加 build/runtime/env/.env 到 .gitignore"
    fi

    if grep -q "build/runtime/secrets/" "$PROJECT_ROOT/.gitignore"; then
        check "secrets 在 .gitignore 中" "pass"
    else
        check "secrets 在 .gitignore 中" "warn" "建议添加 build/runtime/secrets/ 到 .gitignore"
    fi
else
    check ".gitignore 文件" "fail"
fi
echo ""

# 4. Docker 配置检查
echo -e "${YELLOW}[4] Docker 安全配置${NC}"
if [ -f "$PROJECT_ROOT/docker/docker-compose.yml" ]; then
    if grep -q "read_only: true" "$PROJECT_ROOT/docker/docker-compose.yml"; then
        check "只读文件系统" "pass"
    else
        check "只读文件系统" "fail" "建议添加 read_only: true"
    fi

    if grep -q "cap_drop:" "$PROJECT_ROOT/docker/docker-compose.yml"; then
        check "Linux 能力限制" "pass"
    else
        check "Linux 能力限制" "warn" "建议添加 cap_drop: ALL"
    fi

    if grep -q "no-new-privileges:true" "$PROJECT_ROOT/docker/docker-compose.yml"; then
        check "禁止提权" "pass"
    else
        check "禁止提权" "warn" "建议添加 no-new-privileges:true"
    fi
else
    check "docker-compose.yml" "fail"
fi
echo ""

# 5. 网络配置检查
echo -e "${YELLOW}[5] 网络配置${NC}"
if [ -f "$CONFIG_DIR/openclaw.json" ]; then
    host=$(grep -o '"host"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_DIR/openclaw.json" | cut -d'"' -f4 || echo "")
    if [ "$host" = "127.0.0.1" ] || [ "$host" = "localhost" ]; then
        check "仅本地绑定" "pass" "绑定地址: $host"
    else
        check "仅本地绑定" "warn" "绑定地址: $host (建议改为 127.0.0.1)"
    fi

    if grep -q '"https"' "$CONFIG_DIR/openclaw.json" && grep -q '"enabled"[[:space:]]*:[[:space:]]*true' "$CONFIG_DIR/openclaw.json"; then
        check "HTTPS 配置" "pass"
    else
        check "HTTPS 配置" "warn" "未启用 (生产环境建议启用)"
    fi
else
    check "openclaw.json" "fail"
fi
echo ""

# 6. Token 强度检查
echo -e "${YELLOW}[6] Token 安全性${NC}"
token=""
if [ -f "$SECRETS_DIR/gateway_token" ]; then
    token=$(cat "$SECRETS_DIR/gateway_token" 2>/dev/null || echo "")
elif [ -f "$ENV_FILE" ]; then
    token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
fi

if [ -n "$token" ]; then
    token_len=${#token}
    if [ "$token_len" -ge 32 ]; then
        check "Token 长度" "pass" "长度: $token_len 字符"
    else
        check "Token 长度" "fail" "长度: $token_len 字符 (建议至少 32 字符)"
    fi

    if [[ "$token" =~ ^[a-f0-9]+$ ]]; then
        check "Token 格式" "pass" "使用十六进制格式"
    else
        check "Token 格式" "warn" "建议使用随机十六进制格式"
    fi
else
    check "Token 配置" "fail" "未找到 Token"
fi
echo ""

# 7. 日志配置检查
echo -e "${YELLOW}[7] 日志安全${NC}"
if [ -f "$CONFIG_DIR/openclaw.json" ]; then
    if grep -q '"sanitize"[[:space:]]*:[[:space:]]*true' "$CONFIG_DIR/openclaw.json"; then
        check "日志脱敏" "pass"
    else
        check "日志脱敏" "warn" "建议启用日志脱敏"
    fi

    if grep -q '"excludePaths"' "$CONFIG_DIR/openclaw.json"; then
        check "敏感路径排除" "pass"
    else
        check "敏感路径排除" "warn"
    fi
else
    check "openclaw.json" "fail"
fi
echo ""

# 8. 速率限制检查
echo -e "${YELLOW}[8] 访问控制${NC}"
if [ -f "$CONFIG_DIR/openclaw.json" ]; then
    if grep -q '"rateLimit"' "$CONFIG_DIR/openclaw.json" && grep -q '"enabled"[[:space:]]*:[[:space:]]*true' "$CONFIG_DIR/openclaw.json"; then
        check "速率限制" "pass"
    else
        check "速率限制" "warn"
    fi

    if grep -q '"ipWhitelist"' "$CONFIG_DIR/openclaw.json" && grep -q '"enabled"[[:space:]]*:[[:space:]]*true' "$CONFIG_DIR/openclaw.json"; then
        check "IP 白名单" "pass"
    else
        check "IP 白名单" "warn"
    fi
else
    check "openclaw.json" "fail"
fi
echo ""

# 总结
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  检查结果汇总${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "  ${GREEN}通过: $PASSED_CHECKS${NC}"
echo -e "  ${YELLOW}警告: $WARNING_CHECKS${NC}"
echo -e "  ${RED}失败: $FAILED_CHECKS${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ] && [ "$WARNING_CHECKS" -eq 0 ]; then
    echo -e "${GREEN}✓ 所有安全检查通过!${NC}"
elif [ "$FAILED_CHECKS" -eq 0 ]; then
    echo -e "${YELLOW}⚠ 安全配置良好,建议关注警告项${NC}"
else
    echo -e "${RED}✗ 存在安全风险,建议修复失败项${NC}"
fi

echo ""
echo "改进建议:"
if [ ! -d "$SECRETS_DIR" ] || [ ! -f "$SECRETS_DIR/gateway_token" ]; then
    echo "  1. 迁移到 Docker Secrets 模式:"
    echo "     ./scripts/migrate_token.sh --migrate"
fi
echo "  2. 启用 HTTPS (生产环境):"
echo "     编辑 config/openclaw.json 设置 security.https"
echo "  3. 定期轮换 Token:"
echo "     ./scripts/rotate_token.sh --rotate"
echo ""

# 返回状态码
if [ "$FAILED_CHECKS" -gt 0 ]; then
    exit 1
elif [ "$WARNING_CHECKS" -gt 0 ]; then
    exit 2
else
    exit 0
fi
