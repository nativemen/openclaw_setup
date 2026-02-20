#!/bin/bash

###############################################################################
# OpenClaw 健康检查脚本
###############################################################################

# 严格模式
set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

GATEWAY_URL="${1:-http://localhost:18789}"

echo "=========================================="
echo "  OpenClaw 健康检查"
echo "=========================================="
echo ""

# 检查 Gateway 服务
check_gateway() {
    echo -n "检查 Gateway 服务... "

    if curl -sf "$GATEWAY_URL/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 正常${NC}"
        return 0
    else
        echo -e "${RED}✗ 失败${NC}"
        return 1
    fi
}

# 检查 Docker 容器
check_docker() {
    echo -n "检查 Docker 容器... "

    if docker ps --format '{{.Names}}' | grep -q "openclaw-gateway"; then
        local status=$(docker ps --filter "name=openclaw-gateway" --format '{{.Status}}')
        echo -e "${GREEN}✓ 运行中 ($status)${NC}"
        return 0
    else
        echo -e "${YELLOW}! 未运行${NC}"
        return 1
    fi
}

# 检查端口
check_port() {
    echo -n "检查端口 18789... "

    if netstat -tuln 2>/dev/null | grep -q ":18789" || ss -tuln 2>/dev/null | grep -q ":18789"; then
        echo -e "${GREEN}✓ 监听中${NC}"
        return 0
    else
        echo -e "${RED}✗ 未监听${NC}"
        return 1
    fi
}

# 检查环境变量（多提供商支持）
check_env() {
    echo "检查配置..."

    # 检查两个可能的配置文件位置
    local env_file_project="$PROJECT_ROOT/build/runtime/env/.env"
    local env_file_home="$HOME/.openclaw/.env"
    local env_file_docker="$PROJECT_ROOT/build/docker/.env"

    # 优先使用 docker/.env
    local env_file=""
    if [ -f "$env_file_docker" ]; then
        env_file="$env_file_docker"
        echo -e "  ${GREEN}✓${NC} 配置文件存在: $env_file_docker"
    elif [ -f "$env_file_project" ]; then
        env_file="$env_file_project"
        echo -e "  ${GREEN}✓${NC} 配置文件存在: $env_file_project"
    elif [ -f "$env_file_home" ]; then
        env_file="$env_file_home"
        echo -e "  ${GREEN}✓${NC} 配置文件存在: $env_file_home"
    else
        echo -e "  ${YELLOW}!${NC} 配置文件不存在"
        echo -e "  ${YELLOW}!${NC} 预期位置: $env_file_docker, $env_file_project 或 $env_file_home"
        return
    fi

    # 加载环境变量
    source "$env_file" 2>/dev/null || true

    echo ""
    echo "  多提供商 API Keys 配置:"

    # 检查所有提供商的 API Keys
    local configured_count=0

    if [ -n "$DEEPSEEK_API_KEY" ] && [ "$DEEPSEEK_API_KEY" != "your-api-key-here" ]; then
        echo -e "    ${GREEN}✓${NC} DeepSeek API Key 已配置"
        ((configured_count++))
    else
        echo -e "    ${YELLOW}!${NC} DeepSeek API Key 未配置"
    fi

    if [ -n "$ANTHROPIC_API_KEY" ] && [ "$ANTHROPIC_API_KEY" != "your-api-key-here" ]; then
        echo -e "    ${GREEN}✓${NC} Anthropic (Claude) API Key 已配置"
        ((configured_count++))
    else
        echo -e "    ${YELLOW}!${NC} Anthropic (Claude) API Key 未配置"
    fi

    if [ -n "$GEMINI_API_KEY" ] && [ "$GEMINI_API_KEY" != "your-api-key-here" ]; then
        echo -e "    ${GREEN}✓${NC} Google Gemini API Key 已配置"
        ((configured_count++))
    else
        echo -e "    ${YELLOW}!${NC} Google Gemini API Key 未配置"
    fi

    echo ""
    if [ $configured_count -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} 共 $configured_count 个提供商已配置 (支持运行时切换)"
    else
        echo -e "  ${RED}✗${NC} 未配置任何提供商 API Key"
    fi

    # 显示当前默认提供商
    if [ -n "$AI_PROVIDER" ]; then
        echo ""
        echo -e "  ${GREEN}✓${NC} 当前默认 AI Provider: $AI_PROVIDER"
        [ -n "$AI_MODEL" ] && echo -e "  ${GREEN}✓${NC} 默认模型: $AI_MODEL"
    else
        echo -e "  ${YELLOW}!${NC} AI Provider 未配置"
    fi
}

# 检查 Ollama
check_ollama() {
    echo -n "检查 Ollama 服务... "

    if command -v ollama &> /dev/null; then
        if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 运行中${NC}"
            echo "  已下载模型:"
            ollama list | tail -n +2 | head -5
        else
            echo -e "${YELLOW}! 已安装但未运行${NC}"
        fi
    else
        echo -e "${YELLOW}! 未安装${NC}"
    fi
}

# 检查代理连接
check_proxy() {
    if [ -n "$HTTP_PROXY" ]; then
        echo -n "检查代理连接... "
        if curl -sf -x "$HTTP_PROXY" https://api.anthropic.com > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 正常 ($HTTP_PROXY)${NC}"
        else
            echo -e "${RED}✗ 失败${NC}"
        fi
    fi
}

# 获取 Gateway 状态
get_status() {
    echo ""
    echo "=========================================="
    echo "Gateway 状态信息"
    echo "=========================================="

    curl -sf "$GATEWAY_URL/api/status" 2>/dev/null | head -50 || echo "无法获取状态"
}

# 主函数
main() {
    local failed=0

    check_gateway || ((failed++))
    check_docker || ((failed++))
    check_port || ((failed++))
    check_ollama
    check_env
    check_proxy

    echo ""

    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}所有检查通过!${NC}"

        echo ""
        echo "访问地址:"
        echo "  - Web UI: $GATEWAY_URL"
        echo "  - API: $GATEWAY_URL/api/"

        # 可选: 显示状态
        # get_status
    else
        echo -e "${RED}有 $failed 项检查失败${NC}"
        exit 1
    fi
}

main "$@"
