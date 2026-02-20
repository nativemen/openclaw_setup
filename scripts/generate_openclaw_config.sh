#!/bin/bash

###############################################################################
# OpenClaw 动态配置文件生成脚本
# 根据用户输入的 API Keys 动态生成 openclaw.json
# 只包含实际配置了 API Key 的提供商，避免未配置密钥的提供商导致错误
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
CONFIG_DIR="$PROJECT_ROOT/config"
ENV_FILE="$BUILD_DIR/runtime/env/.env"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  生成 OpenClaw 配置文件${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 从环境变量文件读取 API Key
get_api_key() {
    local key_name="$1"
    if [ -f "$ENV_FILE" ]; then
        grep "^${key_name}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo ""
    else
        echo ""
    fi
}

# 检查 API Key 是否有效（非空且不是占位符）
is_valid_key() {
    local key="$1"
    if [ -z "$key" ]; then
        return 1  # false
    fi
    if [ "$key" = "your-api-key-here" ]; then
        return 1  # false
    fi
    return 0  # true
}

# 生成配置文件
generate_config() {
    local output_file="$1"

    # 读取各提供商的 API Keys
    local deepseek_key=$(get_api_key "DEEPSEEK_API_KEY")
    local anthropic_key=$(get_api_key "ANTHROPIC_API_KEY")
    local gemini_key=$(get_api_key "GEMINI_API_KEY")

    # 确定默认提供商（优先使用配置了密钥的）
    local default_provider="deepseek"
    local primary_model="deepseek/deepseek-chat"
    local fallback_models=()

    # 构建 providers JSON
    local providers_json=""
    local first_provider=true

    # DeepSeek 提供商
    if is_valid_key "$deepseek_key"; then
        if [ "$first_provider" = true ]; then
            first_provider=false
            default_provider="deepseek"
            primary_model="deepseek/deepseek-chat"
        else
            fallback_models+=("deepseek/deepseek-chat")
        fi

        providers_json+='
    "deepseek": {
      "baseUrl": "https://api.deepseek.com/v1",
      "apiKey": "${DEEPSEEK_API_KEY}",
      "api": "openai-completions",
      "models": [
        {
          "id": "deepseek-chat",
          "name": "DeepSeek Chat",
          "contextWindow": 64000,
          "maxTokens": 8192
        },
        {
          "id": "deepseek-coder",
          "name": "DeepSeek Coder",
          "contextWindow": 64000,
          "maxTokens": 8192
        },
        {
          "id": "deepseek-reasoner",
          "name": "DeepSeek Reasoner (R1)",
          "contextWindow": 64000,
          "maxTokens": 8192
        }
      ]
    }'
    fi

    # Anthropic 提供商
    if is_valid_key "$anthropic_key"; then
        if [ "$first_provider" = true ]; then
            first_provider=false
            default_provider="anthropic"
            primary_model="anthropic/claude-sonnet-4-5"
        else
            fallback_models+=("anthropic/claude-sonnet-4-5")
        fi

        # 添加逗号分隔符（如果前面有提供商）
        if [ -n "$providers_json" ]; then
            providers_json+=',
'
        fi

        providers_json+='
    "anthropic": {
      "baseUrl": "https://api.anthropic.com/v1",
      "apiKey": "${ANTHROPIC_API_KEY}",
      "api": "anthropic-messages",
      "models": [
        {
          "id": "claude-opus-4-6",
          "name": "Claude Opus 4.6",
          "contextWindow": 200000,
          "maxTokens": 8192
        },
        {
          "id": "claude-sonnet-4-5",
          "name": "Claude Sonnet 4.5",
          "contextWindow": 200000,
          "maxTokens": 8192
        }
      ]
    }'
    fi

    # Google/Gemini 提供商
    if is_valid_key "$gemini_key"; then
        if [ "$first_provider" = true ]; then
            first_provider=false
            default_provider="google"
            primary_model="google/gemini-2.0-flash"
        else
            fallback_models+=("google/gemini-2.0-flash")
        fi

        # 添加逗号分隔符（如果前面有提供商）
        if [ -n "$providers_json" ]; then
            providers_json+=',
'
        fi

        providers_json+='
    "google": {
      "baseUrl": "https://generativelanguage.googleapis.com/v1beta",
      "apiKey": "${GEMINI_API_KEY}",
      "api": "openai-completions",
      "models": [
        {
          "id": "gemini-2.0-flash",
          "name": "Gemini 2.0 Flash",
          "contextWindow": 1000000,
          "maxTokens": 8192
        },
        {
          "id": "gemini-2.0-pro",
          "name": "Gemini 2.0 Pro",
          "contextWindow": 2000000,
          "maxTokens": 8192
        }
      ]
    }'
    fi

    # 如果没有配置任何提供商，使用 DeepSeek 作为占位（避免完全空配置）
    if [ "$first_provider" = true ]; then
        echo -e "${YELLOW}警告: 未配置任何有效的 API Key${NC}"
        echo -e "${YELLOW}将生成最小配置，请运行 start_gateway.sh 配置 API Keys${NC}"

        providers_json='
    "deepseek": {
      "baseUrl": "https://api.deepseek.com/v1",
      "apiKey": "${DEEPSEEK_API_KEY}",
      "api": "openai-completions",
      "models": [
        {
          "id": "deepseek-chat",
          "name": "DeepSeek Chat",
          "contextWindow": 64000,
          "maxTokens": 8192
        }
      ]
    }'
    fi

    # 构建 fallback models JSON 数组
    local fallbacks_json=""
    local first_fallback=true
    for model in "${fallback_models[@]}"; do
        if [ "$first_fallback" = true ]; then
            first_fallback=false
        else
            fallbacks_json+=',
        '
        fi
        fallbacks_json+="\"$model\""
    done

    # 构建 agents models 配置
    local agents_models_json=""

    # 根据配置的提供商添加对应的模型别名
    if is_valid_key "$deepseek_key"; then
        agents_models_json+='
        "deepseek/deepseek-chat": {
          "alias": "DeepSeek Chat"
        },
        "deepseek/deepseek-coder": {
          "alias": "DeepSeek Coder"
        },
        "deepseek/deepseek-reasoner": {
          "alias": "DeepSeek R1"
        }'
    fi

    if is_valid_key "$anthropic_key"; then
        if [ -n "$agents_models_json" ]; then
            agents_models_json+=',
'
        fi
        agents_models_json+='
        "anthropic/claude-opus-4-6": {
          "alias": "Claude Opus"
        },
        "anthropic/claude-sonnet-4-5": {
          "alias": "Claude Sonnet"
        }'
    fi

    if is_valid_key "$gemini_key"; then
        if [ -n "$agents_models_json" ]; then
            agents_models_json+=',
'
        fi
        agents_models_json+='
        "google/gemini-2.0-flash": {
          "alias": "Gemini Flash"
        },
        "google/gemini-2.0-pro": {
          "alias": "Gemini Pro"
        }'
    fi

    # 生成完整的配置文件
    cat > "$output_file" << EOF
{
  "gateway": {
    "mode": "local",
    "port": 18789
  },
  "models": {
    "mode": "merge",
    "providers": {
${providers_json}
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${primary_model}",
        "fallbacks": [
        ${fallbacks_json}
        ]
      },
      "models": {
${agents_models_json}
      }
    },
    "list": [
      {
        "id": "main",
        "default": true,
        "name": "Main Agent",
        "model": "${primary_model}"
      }
    ]
  }
}
EOF

    echo -e "${GREEN}✓ 配置文件已生成: $output_file${NC}"
    echo ""
    echo "配置的提供商:"
    is_valid_key "$deepseek_key" && echo "  ✓ DeepSeek"
    is_valid_key "$anthropic_key" && echo "  ✓ Anthropic (Claude)"
    is_valid_key "$gemini_key" && echo "  ✓ Google (Gemini)"
    echo ""
    echo "默认提供商: $default_provider"
    echo "主模型: $primary_model"
    echo ""
}

# 备份现有配置
backup_existing_config() {
    local config_file="$1"
    if [ -f "$config_file" ]; then
        # 创建 build 目录下的备份目录
        local backup_dir="$BUILD_DIR/backups/config"
        mkdir -p "$backup_dir"

        # 获取文件名（不含路径）
        local config_filename=$(basename "$config_file")
        local backup_file="${backup_dir}/${config_filename}.backup.$(date +%Y%m%d_%H%M%S)"

        cp "$config_file" "$backup_file"
        echo -e "${YELLOW}已备份现有配置: $backup_file${NC}"
    fi
}

# 主函数
main() {
    local config_file="$CONFIG_DIR/openclaw.json"

    # 检查环境变量文件是否存在
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}警告: 未找到环境变量文件: $ENV_FILE${NC}"
        echo -e "${YELLOW}请先运行 ./scripts/start_gateway.sh 进行初始配置${NC}"
        exit 1
    fi

    # 备份现有配置
    backup_existing_config "$config_file"

    # 生成新配置
    generate_config "$config_file"

    echo -e "${GREEN}配置文件生成完成!${NC}"
    echo ""
    echo "您可以现在启动 Gateway:"
    echo "  ./scripts/start_gateway.sh"
}

main "$@"
