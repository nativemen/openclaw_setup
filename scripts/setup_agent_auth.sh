#!/bin/bash

###############################################################################
# OpenClaw 嵌入式代理认证配置脚本
# 生成 auth-profiles.json 文件供嵌入式代理使用
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
AGENT_DIR="$BUILD_DIR/runtime/agents/main/agent"
AUTH_FILE="$AGENT_DIR/auth-profiles.json"

# 提供商映射：将用户选择的名称映射到实际的提供商 ID
declare -A PROVIDER_MAP
PROVIDER_MAP[claude]="anthropic"
PROVIDER_MAP[deepseek]="deepseek"
PROVIDER_MAP[gemini]="google"
PROVIDER_MAP[ollama]="ollama"

# 提供商显示名称
declare -A PROVIDER_LABELS
PROVIDER_LABELS[claude]="Claude (Anthropic)"
PROVIDER_LABELS[deepseek]="DeepSeek"
PROVIDER_LABELS[gemini]="Gemini (Google)"
PROVIDER_LABELS[ollama]="Ollama (Local)"

# 提供商 API Key 环境变量名映射
declare -A PROVIDER_API_KEY_NAMES
PROVIDER_API_KEY_NAMES[claude]="ANTHROPIC_API_KEY"
PROVIDER_API_KEY_NAMES[deepseek]="DEEPSEEK_API_KEY"
PROVIDER_API_KEY_NAMES[gemini]="GEMINI_API_KEY"
PROVIDER_API_KEY_NAMES[ollama]="OLLAMA_API_KEY"

# 创建必要的目录结构
create_directories() {
    echo -e "${BLUE}创建代理认证目录...${NC}"
    mkdir -p "$AGENT_DIR"
    chmod 700 "$AGENT_DIR"
    echo -e "${GREEN}✓ 目录创建完成: $AGENT_DIR${NC}"
}

# 清理和验证提供商名称，防止重复
clean_provider_name() {
    local input="$1"
    local cleaned="$input"

    # 移除常见的重复模式
    # 如果字符串包含重复的子串（如 deepseekdeepseek），提取唯一部分
    local len=${#cleaned}
    if [ $len -gt 0 ]; then
        local half_len=$((len / 2))
        if [ $half_len -gt 0 ]; then
            local first_half="${cleaned:0:$half_len}"
            local second_half="${cleaned:$half_len:$half_len}"
            if [ "$first_half" = "$second_half" ]; then
                cleaned="$first_half"
            fi
        fi
    fi

    # 转换为小写并移除多余空格
    cleaned=$(echo "$cleaned" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    echo "$cleaned"
}

# 从 .env 文件读取配置
load_env_config() {
    local env_file="$BUILD_DIR/runtime/env/.env"
    local docker_env_file="$BUILD_DIR/docker/.env"
    local source_file=""

    # 优先使用 build/runtime/env/.env，如果不存在则尝试 build/docker/.env
    if [ -f "$env_file" ]; then
        source_file="$env_file"
        echo -e "${BLUE}从 build/runtime/env/.env 读取配置${NC}"
    elif [ -f "$docker_env_file" ]; then
        source_file="$docker_env_file"
        echo -e "${YELLOW}build/runtime/env/.env 不存在，从 build/docker/.env 读取配置${NC}"
    else
        echo -e "${RED}错误: 未找到 .env 文件${NC}"
        echo "  请确保以下文件之一存在:"
        echo "    - $env_file"
        echo "    - $docker_env_file"
        return 1
    fi

    # 读取 AI_PROVIDER
    AI_PROVIDER=$(grep "^AI_PROVIDER=" "$source_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '[:space:]' || echo "")

    # 清理提供商名称，防止重复
    AI_PROVIDER=$(clean_provider_name "$AI_PROVIDER")

    # 读取 provider 专用的 API Key
    local provider_key_name=""
    if [[ -n "$AI_PROVIDER" && -v "PROVIDER_API_KEY_NAMES[$AI_PROVIDER]" ]]; then
        provider_key_name="${PROVIDER_API_KEY_NAMES[$AI_PROVIDER]}"
    fi
    AI_API_KEY=""
    if [ -n "$provider_key_name" ]; then
        AI_API_KEY=$(grep "^${provider_key_name}=" "$source_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    fi

    # 读取 AI_MODEL
    AI_MODEL=$(grep "^AI_MODEL=" "$source_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '[:space:]' || echo "")

    # 读取 AI_API_BASE_URL
    AI_API_BASE_URL=$(grep "^AI_API_BASE_URL=" "$source_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '[:space:]' || echo "")

    echo -e "${BLUE}读取配置:${NC}"
    echo "  - AI_PROVIDER: ${AI_PROVIDER:-未设置}"
    echo "  - AI_MODEL: ${AI_MODEL:-未设置}"
    echo "  - AI_API_KEY: $([ -n "$AI_API_KEY" ] && echo "已设置" || echo "未设置")"

    # 如果两个文件都存在但配置不一致，给出警告
    if [ -f "$env_file" ] && [ -f "$docker_env_file" ]; then
        local docker_provider=$(grep "^AI_PROVIDER=" "$docker_env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '[:space:]' || echo "")
        if [ -n "$AI_PROVIDER" ] && [ -n "$docker_provider" ] && [ "$AI_PROVIDER" != "$docker_provider" ]; then
            echo ""
            echo -e "${YELLOW}警告: AI 提供商配置不一致!${NC}"
            echo "  build/runtime/env/.env: $AI_PROVIDER"
            echo "  build/docker/.env:      $docker_provider"
            echo -e "${BLUE}提示: 运行 ./scripts/start_gateway.sh 可同步配置${NC}"
            echo ""
        fi
    fi
}

# 生成 auth-profiles.json 文件
generate_auth_profiles() {
    local provider="$1"
    local api_key="$2"
    local model="$3"
    local api_base_url="$4"

    # 清理提供商名称，防止重复
    provider=$(clean_provider_name "$provider")

    # 映射到实际的提供商 ID
    local actual_provider="${PROVIDER_MAP[$provider]:-$provider}"
    local provider_label="${PROVIDER_LABELS[$provider]:-$provider}"

    # 再次清理，确保没有重复
    actual_provider=$(clean_provider_name "$actual_provider")

    echo -e "${BLUE}生成 auth-profiles.json...${NC}"
    echo "  - 用户选择: $provider"
    echo "  - 实际提供商: $actual_provider"
    echo "  - 模型: $model"

    # 创建 JSON 文件
    cat > "$AUTH_FILE" << EOF
{
  "version": "1.0",
  "defaultProvider": "$actual_provider",
  "profiles": {
    "$actual_provider": {
      "provider": "$actual_provider",
      "label": "$provider_label",
      "apiKey": "$api_key",
      "model": "$model",
      "apiBaseUrl": "$api_base_url",
      "enabled": true,
      "default": true
    }
  }
}
EOF

    # 设置权限
    chmod 600 "$AUTH_FILE"

    echo -e "${GREEN}✓ 认证文件已生成: $AUTH_FILE${NC}"
}

# 生成嵌入式代理配置文件
generate_agent_config() {
    local provider="$1"
    local model="$2"

    # 清理提供商名称
    provider=$(clean_provider_name "$provider")

    local config_file="$AGENT_DIR/config.json"
    local actual_provider="${PROVIDER_MAP[$provider]:-$provider}"
    actual_provider=$(clean_provider_name "$actual_provider")

    echo -e "${BLUE}生成代理配置文件...${NC}"

    cat > "$config_file" << EOF
{
  "agent": {
    "model": "$actual_provider/$model",
    "provider": "$actual_provider",
    "maxTokens": 8192,
    "temperature": 0.7,
    "timeout": 120000
  }
}
EOF

    chmod 600 "$config_file"
    echo -e "${GREEN}✓ 代理配置已生成: $config_file${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  OpenClaw 嵌入式代理认证配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    # 1. 创建目录
    create_directories

    # 2. 加载环境变量
    if ! load_env_config; then
        echo -e "${RED}无法加载配置，退出${NC}"
        exit 1
    fi

    # 3. 验证配置
    if [ -z "$AI_PROVIDER" ]; then
        echo -e "${RED}错误: AI_PROVIDER 未设置${NC}"
        exit 1
    fi

    # 检查 provider 专用的 API Key
    local provider_key_name=""
    if [[ -n "$AI_PROVIDER" && -v "PROVIDER_API_KEY_NAMES[$AI_PROVIDER]" ]]; then
        provider_key_name="${PROVIDER_API_KEY_NAMES[$AI_PROVIDER]}"
    fi
    local provider_key_value=""
    if [ -n "$provider_key_name" ]; then
        provider_key_value=$(grep "^${provider_key_name}=" "$BUILD_DIR/runtime/env/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    fi
    if [ -z "$provider_key_value" ] && [ "$AI_PROVIDER" != "ollama" ]; then
        echo -e "${YELLOW}警告: ${provider_key_name} 未设置 (ollama 除外)${NC}"
    fi

    # 4. 生成认证文件
    generate_auth_profiles "$AI_PROVIDER" "$AI_API_KEY" "$AI_MODEL" "$AI_API_BASE_URL"

    # 5. 生成代理配置
    generate_agent_config "$AI_PROVIDER" "$AI_MODEL"

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  嵌入式代理认证配置完成${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "配置文件位置:"
    echo "  - $AUTH_FILE"
    echo "  - $AGENT_DIR/config.json"
    echo ""
    echo "这些文件将在 Docker 启动时挂载到容器内的:"
    echo "  - /home/node/.openclaw/agents/main/agent/"
    echo ""
}

main "$@"
