#!/bin/bash

###############################################################################
# OpenClaw Gateway 启动脚本
# 支持交互式选择 AI 大模型
###############################################################################

# 严格模式: 脚本在任何命令失败时立即退出
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
DOCKER_DIR="$PROJECT_ROOT/docker"
RUNTIME_ENV_DIR="$BUILD_DIR/runtime/env"
TEMPLATE_ENV_DIR="$PROJECT_ROOT/config/env"

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
echo -e "${GREEN}使用 Docker Compose: $DOCKER_COMPOSE${NC}"

echo -e "${GREEN}启动 OpenClaw Gateway...${NC}"

# 检查 Docker 是否运行
check_docker() {
    if docker ps &> /dev/null; then
        return 0
    fi

    echo -e "${RED}错误: Docker 未运行${NC}"
    echo "请先启动 Docker"

    # 检测是否在 WSL 中
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo ""
        echo "WSL2 中启动 Docker:"
        echo "  方法1: 启动 Docker Desktop (如果已安装)"
        echo "  方法2: 运行: sudo service docker start"
        echo "  方法3: 运行: sudo dockerd &"
    fi

    return 1
}

# 调用检查
if ! check_docker; then
    exit 1
fi

# AI 提供商配置映射
declare -A PROVIDER_API_BASE_URLS
PROVIDER_API_BASE_URLS[deepseek]="https://api.deepseek.com"
PROVIDER_API_BASE_URLS[gemini]="https://generativelanguage.googleapis.com"
PROVIDER_API_BASE_URLS[claude]="https://api.anthropic.com"
PROVIDER_API_BASE_URLS[ollama]="http://localhost:11434"

declare -A PROVIDER_DEFAULT_MODELS
PROVIDER_DEFAULT_MODELS[deepseek]="deepseek-chat"
PROVIDER_DEFAULT_MODELS[gemini]="gemini-2.0-flash"
PROVIDER_DEFAULT_MODELS[claude]="claude-sonnet-4-20250514"
PROVIDER_DEFAULT_MODELS[ollama]="llama3.1:8b"

declare -A PROVIDER_API_KEY_NAMES
PROVIDER_API_KEY_NAMES[deepseek]="DEEPSEEK_API_KEY"
PROVIDER_API_KEY_NAMES[gemini]="GEMINI_API_KEY"
PROVIDER_API_KEY_NAMES[claude]="ANTHROPIC_API_KEY"
PROVIDER_API_KEY_NAMES[ollama]="OLLAMA_API_KEY"

# 多提供商 API Key 变量名列表（用于配置所有提供商）
ALL_PROVIDER_API_KEYS=("DEEPSEEK_API_KEY" "GEMINI_API_KEY" "ANTHROPIC_API_KEY")

# 显示名称映射
declare -A PROVIDER_DISPLAY_NAMES
PROVIDER_DISPLAY_NAMES[deepseek]="DeepSeek"
PROVIDER_DISPLAY_NAMES[gemini]="Gemini"
PROVIDER_DISPLAY_NAMES[claude]="Claude"
PROVIDER_DISPLAY_NAMES[ollama]="Ollama"

# 检测是否首次运行（无 .env 文件）
is_first_run() {
    local env_file="$RUNTIME_ENV_DIR/.env"
    if [ ! -f "$env_file" ]; then
        return 0  # true - 是首次运行
    fi
    # 检查文件是否为空或缺少关键配置
    if ! grep -q "^AI_PROVIDER=" "$env_file" 2>/dev/null; then
        return 0  # true - 是首次运行
    fi
    return 1  # false - 不是首次运行
}

# 创建初始配置
create_initial_config() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  首次运行 - 创建初始配置${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    local env_file="$RUNTIME_ENV_DIR/.env"
    mkdir -p "$RUNTIME_ENV_DIR"

    # 生成 Gateway Token
    local gateway_token=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)

    # 默认使用 DeepSeek
    local default_provider="deepseek"
    local default_model="${PROVIDER_DEFAULT_MODELS[$default_provider]}"
    local default_api_url="${PROVIDER_API_BASE_URLS[$default_provider]}"

    cat > "$env_file" << EOF
# OpenClaw 环境配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# Gateway Token (自动生成)
OPENCLAW_GATEWAY_TOKEN=$gateway_token

# AI 提供商配置
AI_PROVIDER=$default_provider
AI_MODEL=$default_model
AI_API_BASE_URL=$default_api_url

# 代理配置 (根据需要修改)
# HTTP_PROXY=http://your-proxy:port
# HTTPS_PROXY=http://your-proxy:port
EOF

    echo -e "${GREEN}✓ 已创建初始配置文件: $env_file${NC}"
    echo ""
    echo "默认配置:"
    echo "  - AI 提供商: DeepSeek"
    echo "  - 模型: $default_model"
    echo "  - API 地址: $default_api_url"
    echo ""
    echo -e "${YELLOW}注意: 请编辑 $env_file 文件，配置 DEEPSEEK_API_KEY 为您的实际 API 密钥${NC}"
    echo ""

    # 设置 PROVIDER 变量供后续使用
    PROVIDER="$default_provider"
}

# 交互式选择 AI 提供商（支持更改或保持）
select_provider() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  选择 AI 大模型提供商${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo "请选择要使用的 AI 提供商:"
    echo ""
    echo "  1) DeepSeek  (DeepSeek, 推荐)"
    echo "  2) Gemini    (Google)"
    echo "  3) Claude     (Anthropic)"
    echo "  4) Ollama    (本地模型，离线可用)"
    echo ""

    # 始终默认使用 DeepSeek（推荐提供商）
    CURRENT_PROVIDER="deepseek"

    # 获取显示名称
    DISPLAY_NAME="${PROVIDER_DISPLAY_NAMES[$CURRENT_PROVIDER]:-$CURRENT_PROVIDER}"

    read -p "请输入选项 (1-4) [默认: $DISPLAY_NAME]: " choice

    # 设置默认值
    if [ -z "$choice" ]; then
        case "$CURRENT_PROVIDER" in
            deepseek) choice="1" ;;
            gemini) choice="2" ;;
            claude) choice="3" ;;
            ollama) choice="4" ;;
            *) choice="1" ;;
        esac
    fi

    case "$choice" in
        1) PROVIDER="deepseek" ;;
        2) PROVIDER="gemini" ;;
        3) PROVIDER="claude" ;;
        4) PROVIDER="ollama" ;;
        *)
            echo -e "${RED}无效选择，使用默认值 deepseek${NC}"
            PROVIDER="deepseek"
            ;;
    esac

    echo ""
    echo -e "已选择: ${GREEN}$PROVIDER${NC}"
    echo ""
}

# 交互式配置 API Key（支持多提供商）
configure_api_key() {
    local provider="$1"
    local env_file="$2"

    # 获取该 provider 对应的 API Key 变量名
    local key_name="${PROVIDER_API_KEY_NAMES[$provider]}"

    # 检查该 provider 的 API Key
    local old_api_key=""
    if [ -n "$key_name" ]; then
        old_api_key=$(grep "^${key_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    fi

    if [ -n "$old_api_key" ] && [ "$old_api_key" != "your-api-key-here" ]; then
        echo -e "${GREEN}✓ 检测到已配置的 ${key_name}${NC}"
        API_KEY="$old_api_key"
    else
        echo -e "${YELLOW}请配置 ${key_name}:${NC}"
        if [ "$provider" == "ollama" ]; then
            echo "  Ollama 本地模型无需 API Key，直接回车继续"
            read -p "API Key (直接回车): " -s API_KEY
            echo ""
        else
            case "$provider" in
                claude)
                    echo "  访问 https://console.anthropic.com/ 获取 API Key"
                    ;;
                deepseek)
                    echo "  访问 https://platform.deepseek.com/ 获取 API Key"
                    ;;
                gemini)
                    echo "  访问 https://aistudio.google.com/app/apikey 获取 API Key"
                    ;;
            esac
            read -p "API Key: " API_KEY
        fi
    fi
}

# 配置所有提供商的 API Keys（用于多提供商支持）
configure_all_provider_keys() {
    local env_file="$1"

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  配置多提供商 API Keys${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo "您可以配置多个提供商的 API Key，支持运行时切换"
    echo ""

    # DeepSeek
    local deepseek_key=""
    if grep -q "^DEEPSEEK_API_KEY=" "$env_file" 2>/dev/null; then
        deepseek_key=$(grep "^DEEPSEEK_API_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    fi
    if [ -n "$deepseek_key" ] && [ "$deepseek_key" != "your-api-key-here" ]; then
        echo -e "${GREEN}✓ DeepSeek API Key 已配置${NC}"
    else
        echo -e "${YELLOW}配置 DeepSeek API Key (默认提供商):${NC}"
        echo "  访问 https://platform.deepseek.com/ 获取"
        read -p "DeepSeek API Key: " deepseek_key
        if [ -n "$deepseek_key" ]; then
            update_provider_key_in_env "$env_file" "DEEPSEEK_API_KEY" "$deepseek_key"
        fi
    fi

    # Gemini
    local gemini_key=""
    if grep -q "^GEMINI_API_KEY=" "$env_file" 2>/dev/null; then
        gemini_key=$(grep "^GEMINI_API_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    fi
    if [ -n "$gemini_key" ] && [ "$gemini_key" != "your-api-key-here" ]; then
        echo -e "${GREEN}✓ Gemini API Key 已配置${NC}"
    else
        echo ""
        echo -e "${YELLOW}配置 Gemini API Key (可选，用于备用):${NC}"
        echo "  访问 https://aistudio.google.com/app/apikey 获取"
        read -p "Gemini API Key (直接回车跳过): " gemini_key
        if [ -n "$gemini_key" ]; then
            update_provider_key_in_env "$env_file" "GEMINI_API_KEY" "$gemini_key"
        else
            # 如果没有配置 Gemini，设置为空字符串占位
            update_provider_key_in_env "$env_file" "GEMINI_API_KEY" ""
        fi
    fi

    # Anthropic
    local anthropic_key=""
    if grep -q "^ANTHROPIC_API_KEY=" "$env_file" 2>/dev/null; then
        anthropic_key=$(grep "^ANTHROPIC_API_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    fi
    if [ -n "$anthropic_key" ] && [ "$anthropic_key" != "your-api-key-here" ]; then
        echo -e "${GREEN}✓ Anthropic API Key 已配置${NC}"
    else
        echo ""
        echo -e "${YELLOW}配置 Anthropic API Key (可选，用于备用):${NC}"
        echo "  访问 https://console.anthropic.com/ 获取"
        read -p "Anthropic API Key (直接回车跳过): " anthropic_key
        if [ -n "$anthropic_key" ]; then
            update_provider_key_in_env "$env_file" "ANTHROPIC_API_KEY" "$anthropic_key"
        else
            # 如果没有配置 Anthropic，设置为空字符串占位
            update_provider_key_in_env "$env_file" "ANTHROPIC_API_KEY" ""
        fi
    fi

    echo ""
    echo -e "${GREEN}✓ 多提供商 API Keys 配置完成${NC}"
    echo ""
}

# 更新单个提供商的 API Key 到环境文件
update_provider_key_in_env() {
    local env_file="$1"
    local key_name="$2"
    local key_value="$3"

    # 检查是否存在已存在的 key（可能是注释或非注释形式）
    local commented_line=false
    if grep -q "^# ${key_name}=" "$env_file" 2>/dev/null; then
        commented_line=true
        # 取消注释并更新值
        sed -i "s|^# ${key_name}=.*|${key_name}=${key_value}|" "$env_file"
    elif grep -q "^${key_name}=" "$env_file" 2>/dev/null; then
        # 已存在未注释的行，直接更新
        sed -i "s|^${key_name}=.*|${key_name}=${key_value}|" "$env_file"
    else
        # 不存在，追加新行
        echo "${key_name}=${key_value}" >> "$env_file"
    fi
}

# 确保 .env 文件存在（从模板复制或创建最小配置）
ensure_env_file() {
    local env_file="$RUNTIME_ENV_DIR/.env"

    if [ -f "$env_file" ]; then
        return 0
    fi

    mkdir -p "$RUNTIME_ENV_DIR"

    if [ -f "$TEMPLATE_ENV_DIR/.env.template" ]; then
        cp "$TEMPLATE_ENV_DIR/.env.template" "$env_file"
        echo "  从模板创建 .env 文件"
    else
        # 模板不存在，创建最小配置
        cat > "$env_file" << EOF
# OpenClaw 环境配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# Gateway Token
OPENCLAW_GATEWAY_TOKEN=

# AI 提供商配置
AI_PROVIDER=deepseek
AI_MODEL=deepseek-chat
AI_API_BASE_URL=https://api.deepseek.com

# API Keys (请填写实际的 API Key)
# DEEPSEEK_API_KEY=your-api-key-here
# ANTHROPIC_API_KEY=your-api-key-here
# GEMINI_API_KEY=your-api-key-here
EOF
        echo "  创建最小 .env 配置"
    fi
}

# 更新环境配置文件
update_env_file() {
    local provider="$1"
    local api_key="$2"
    local env_file="$RUNTIME_ENV_DIR/.env"

    # 确保 .env 文件存在
    ensure_env_file

    # 生成随机 Gateway Token (如果不存在)
    if ! grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null || \
       grep "^OPENCLAW_GATEWAY_TOKEN=$" "$env_file" 2>/dev/null || \
       grep "^OPENCLAW_GATEWAY_TOKEN=$" "$env_file" 2>/dev/null; then
        GATEWAY_TOKEN=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
        # 添加或更新 token
        if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null; then
            sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN|" "$env_file"
        else
            echo "OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN" >> "$env_file"
        fi
    fi

    # 更新 AI_PROVIDER
    if grep -q "^AI_PROVIDER=" "$env_file" 2>/dev/null; then
        sed -i "s|^AI_PROVIDER=.*|AI_PROVIDER=$provider|" "$env_file"
    else
        echo "AI_PROVIDER=$provider" >> "$env_file"
    fi

    # 更新 provider 特定的 key
    local key_name="${PROVIDER_API_KEY_NAMES[$provider]}"
    if [ -n "$api_key" ] && [ -n "$key_name" ]; then
        if grep -q "^${key_name}=" "$env_file" 2>/dev/null; then
            sed -i "s|^${key_name}=.*|${key_name}=$api_key|" "$env_file"
        else
            echo "${key_name}=$api_key" >> "$env_file"
        fi
    fi

    # 更新 AI_MODEL (使用默认值)
    local default_model="${PROVIDER_DEFAULT_MODELS[$provider]}"
    if grep -q "^AI_MODEL=" "$env_file" 2>/dev/null; then
        sed -i "s|^AI_MODEL=.*|AI_MODEL=$default_model|" "$env_file"
    else
        echo "AI_MODEL=$default_model" >> "$env_file"
    fi

    # 更新 AI_API_BASE_URL
    local api_base_url="${PROVIDER_API_BASE_URLS[$provider]}"
    if grep -q "^AI_API_BASE_URL=" "$env_file" 2>/dev/null; then
        sed -i "s|^AI_API_BASE_URL=.*|AI_API_BASE_URL=$api_base_url|" "$env_file"
    else
        echo "AI_API_BASE_URL=$api_base_url" >> "$env_file"
    fi

    # 加载代理配置 (如果 proxy.env 存在)
    if [ -f "$RUNTIME_ENV_DIR/proxy.env" ]; then
        source "$RUNTIME_ENV_DIR/proxy.env" 2>/dev/null || true
    fi
}

# 安全函数: 验证环境变量文件不存在命令注入
validate_env_file() {
    local file="$1"
    if [ -f "$file" ]; then
        # 检查文件是否包含明显的安全问题
        # 允许: 注释(#), 空行, 变量赋值, 引号引用的值
        # 禁止: 命令替换$(...), 反引号`...`, 管道|, &&, ||
        if grep -qE '\$\([^)]+\)|`[^`]+`|\|.*&&|\&\&.*\|' "$file" 2>/dev/null; then
            echo -e "${RED}错误: 环境变量文件包含不安全的内容: $file${NC}"
            return 1
        fi
        return 0
    fi
    return 0
}

# 预检: 确保必要的目录结构存在
preflight_checks() {
    echo -e "${BLUE}执行预检...${NC}"

    # 初始化 build 目录结构
    echo "  初始化 build 目录结构..."
    bash "$SCRIPT_DIR/init_build_dirs.sh"

    # 检查并创建必要的目录
    local dirs=(
        "$BUILD_DIR/runtime/env"
        "$BUILD_DIR/runtime/secrets"
        "$BUILD_DIR/runtime/certs"
        "$BUILD_DIR/docker/input"
        "$BUILD_DIR/docker/workspace"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "  创建目录: $dir"
            mkdir -p "$dir"
        fi
    done

    echo -e "${GREEN}✓ 预检完成${NC}"
    echo ""
}

# 同步设备令牌
sync_device_token() {
    echo -e "${BLUE}同步设备令牌...${NC}"

    local env_file="$RUNTIME_ENV_DIR/.env"
    local config_file="$PROJECT_ROOT/config/openclaw.json"
    local secrets_file="$BUILD_DIR/runtime/secrets/gateway_token"
    local docker_env_file="$BUILD_DIR/docker/.env"

    # 从 .env 文件获取 token
    local env_token=""
    if [ -f "$env_file" ]; then
        env_token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "")
    fi

    # 如果 .env 中没有 token，尝试从 secrets 读取
    if [ -z "$env_token" ] && [ -f "$secrets_file" ]; then
        env_token=$(cat "$secrets_file" 2>/dev/null | tr -d '\n\r' || echo "")
        echo "  从 secrets 文件读取 token"
    fi

    # 如果仍然没有 token，生成一个新的
    if [ -z "$env_token" ]; then
        echo "  生成新的 Gateway Token..."
        env_token=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
    fi

    # 确保 .env 文件存在（从模板复制）
    ensure_env_file

    # 更新 token
    if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null; then
        sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$env_token|" "$env_file"
    else
        echo "OPENCLAW_GATEWAY_TOKEN=$env_token" >> "$env_file"
    fi
    echo "  已更新 build/runtime/env/.env 文件中的 token"

    # 同步到 secrets 文件 (用于 docker-compose.secrets.yml)
    echo "  同步到 secrets 文件..."
    mkdir -p "$BUILD_DIR/runtime/secrets"
    echo "$env_token" > "$secrets_file"
    chmod 600 "$secrets_file"
    echo "  已更新 build/runtime/secrets/gateway_token"

    # 同步到 docker/.env 文件 (Docker Compose 使用)
    echo "  同步到 docker/.env 文件..."
    mkdir -p "$BUILD_DIR/docker"
    if [ -f "$env_file" ]; then
        # 复制完整的 runtime env 文件到 docker 目录
        cp "$env_file" "$docker_env_file"
        echo "  已同步完整的 env 配置到 docker/.env"
    else
        echo "OPENCLAW_GATEWAY_TOKEN=$env_token" > "$docker_env_file"
    fi
    echo "  已更新 docker/.env 文件"

    echo -e "${GREEN}✓ 设备令牌同步完成${NC}"
    echo ""
}

# 加载环境变量
load_environment() {
    local env_file="$RUNTIME_ENV_DIR/.env"
    if [ -f "$env_file" ]; then
        set -a
        source "$env_file" 2>/dev/null || true
        set +a
    fi
}

# 显示 token 信息
show_token_info() {
    local env_file="$RUNTIME_ENV_DIR/.env"
    local secrets_file="$BUILD_DIR/runtime/secrets/gateway_token"
    local token=""

    # 优先从 secrets 读取
    if [ -f "$secrets_file" ]; then
        token=$(cat "$secrets_file" 2>/dev/null | tr -d '\n\r' || echo "")
    fi

    # 回退到 .env
    if [ -z "$token" ] && [ -f "$env_file" ]; then
        token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "")
    fi

    if [ -n "$token" ]; then
        echo -e "${BLUE}当前 Gateway Token:${NC}"
        echo "  ${token:0:16}...${token: -8}"
        echo ""
        echo -e "${YELLOW}提示: 如果遇到 WebSocket 认证失败 (错误 1008)${NC}"
        echo "  请运行: ./scripts/fix_token_mismatch.sh --fix"
        echo ""
    fi
}

# 交互式选择部署模式
select_deploy_mode() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  选择部署模式${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo "请选择部署模式:"
    echo ""
    echo "  1) 开发/测试模式  (使用环境变量，配置简单)"
    echo "  2) 生产模式       (使用 Docker Secrets，更安全)"
    echo ""

    # 检查是否已有 secrets 配置
    local has_secrets=false
    if [ -f "$BUILD_DIR/runtime/secrets/gateway_token" ] && [ -s "$BUILD_DIR/runtime/secrets/gateway_token" ]; then
        has_secrets=true
    fi

    if [ "$has_secrets" = true ]; then
        read -p "请输入选项 (1-2) [默认: 2-生产模式]: " mode_choice
        mode_choice=${mode_choice:-2}
    else
        read -p "请输入选项 (1-2) [默认: 1-开发模式]: " mode_choice
        mode_choice=${mode_choice:-1}
    fi

    case "$mode_choice" in
        1)
            DEPLOY_MODE="dev"
            echo -e "已选择: ${GREEN}开发/测试模式${NC}"
            ;;
        2)
            DEPLOY_MODE="prod"
            echo -e "已选择: ${GREEN}生产模式${NC}"
            # 确保 secrets 文件存在
            if [ "$has_secrets" = false ]; then
                echo -e "${YELLOW}创建 Docker Secrets 配置...${NC}"
                mkdir -p "$BUILD_DIR/runtime/secrets"
                # 从 .env 获取或生成 token
                local token=""
            if [ -f "$RUNTIME_ENV_DIR/.env" ]; then
                token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$RUNTIME_ENV_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || echo "")
            fi

                if [ -z "$token" ]; then
                    token=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
                fi
                echo "$token" > "$BUILD_DIR/runtime/secrets/gateway_token"
                chmod 600 "$BUILD_DIR/runtime/secrets/gateway_token"
                echo -e "${GREEN}✓ 已创建 build/runtime/secrets/gateway_token${NC}"
            fi
            ;;
        *)
            echo -e "${RED}无效选择，使用默认开发模式${NC}"
            DEPLOY_MODE="dev"
            ;;
    esac
    echo ""
}

# 启动 Docker
start_docker() {
    cd "$DOCKER_DIR"

    # env_file 路径 (相对于 docker 目录)
    ENV_FILE="$PROJECT_ROOT/build/docker/.env"

    # 根据部署模式选择 compose 文件
    if [ "$DEPLOY_MODE" = "prod" ]; then
        COMPOSE_ARGS="-f docker-compose.yml -f docker-compose.prod.yml"
        echo -e "${GREEN}✓ 使用生产模式部署${NC}"
        echo -e "${BLUE}  配置文件: docker-compose.yml + docker-compose.prod.yml${NC}"
        echo -e "${BLUE}  安全特性: Docker Secrets, 只读根文件系统${NC}"
    else
        COMPOSE_ARGS="-f docker-compose.yml"
        echo -e "${GREEN}✓ 使用开发/测试模式部署${NC}"
        echo -e "${BLUE}  配置文件: docker-compose.yml${NC}"
        echo -e "${BLUE}  配置方式: 环境变量${NC}"
    fi
    echo ""

    # 清理现有容器
    echo -e "${YELLOW}清理现有容器...${NC}"
    if $DOCKER_COMPOSE --env-file "$ENV_FILE" $COMPOSE_ARGS down 2>/dev/null; then
        echo -e "${GREEN}✓ 现有容器已清理${NC}"
    else
        echo -e "${YELLOW}! 无需清理的容器 (可能尚未运行)${NC}"
    fi
    echo ""

    echo "启动 Docker 容器..."
    # 使用选定的 compose 配置和 env 文件
    if docker compose version &> /dev/null 2>&1; then
        $DOCKER_COMPOSE --env-file "$ENV_FILE" $COMPOSE_ARGS up -d --pull always
    else
        $DOCKER_COMPOSE --env-file "$ENV_FILE" $COMPOSE_ARGS build
        $DOCKER_COMPOSE --env-file "$ENV_FILE" $COMPOSE_ARGS up -d
    fi

    # 等待服务启动
    echo "等待服务启动..."
    sleep 5

    # 检查服务状态
    if $DOCKER_COMPOSE ps | grep -q "openclaw-gateway.*Up"; then
        echo -e "${GREEN}✓ OpenClaw Gateway 已启动${NC}"
        echo ""
        echo "访问地址:"
        echo "  - Web UI: http://localhost:18789"
        echo "  - WebSocket: ws://localhost:18789"
        echo ""
        echo -e "${YELLOW}注意: 如果浏览器显示 'device token mismatch' 错误${NC}"
        echo "  请运行: ./scripts/fix_token_mismatch.sh --fix"
        echo ""

        # 显示当前使用的模型
        echo "当前配置:"
        echo "  - AI 提供商: ${AI_PROVIDER:-未知}"
        echo "  - 模型: ${AI_MODEL:-未知}"
        echo ""

        # 显示日志
        echo "最近日志 (按 Ctrl+C 退出):"
        $DOCKER_COMPOSE logs -f
    else
        echo -e "${RED}启动失败，请检查日志${NC}"
        $DOCKER_COMPOSE logs
        exit 1
    fi
}

# 主函数
main() {
    # 0. 执行预检
    preflight_checks

    # 0.5 同步设备令牌
    sync_device_token

    # 0.6 设置嵌入式代理认证
    echo -e "${BLUE}设置嵌入式代理认证...${NC}"
    if [ -f "$SCRIPT_DIR/setup_agent_auth.sh" ]; then
        "$SCRIPT_DIR/setup_agent_auth.sh"
    else
        echo -e "${YELLOW}警告: 未找到 setup_agent_auth.sh 脚本${NC}"
    fi
    echo ""

    # 1. 检测是否首次运行并处理配置
    if is_first_run; then
        # 首次运行：创建初始配置
        create_initial_config
    else
        # 非首次运行：询问是否更改提供商
        select_provider
    fi

    # 2. 准备环境变量文件
    ENV_FILE="$RUNTIME_ENV_DIR/.env"

    # 确保配置文件存在（统一入口）
    ensure_env_file

    # 3. 配置所有提供商的 API Keys（多提供商支持）
    configure_all_provider_keys "$ENV_FILE"

    # 3.5 生成动态配置文件（根据实际配置的 API Keys）
    echo -e "${BLUE}生成 OpenClaw 配置文件...${NC}"
    if [ -f "$SCRIPT_DIR/generate_openclaw_config.sh" ]; then
        "$SCRIPT_DIR/generate_openclaw_config.sh"
    else
        echo -e "${YELLOW}警告: 未找到 generate_openclaw_config.sh 脚本${NC}"
    fi
    echo ""

    # 4. 获取当前选择提供商的 API Key
    API_KEY=$(grep "^${PROVIDER_API_KEY_NAMES[$PROVIDER]}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")

    # 5. 更新配置文件（使用当前选择的 provider）
    update_env_file "$PROVIDER" "$API_KEY"

    # 4.5 再次同步令牌 (确保新生成的 token 也被同步)
    sync_device_token

    # 4.6 重新生成嵌入式代理认证 (使用新选择的提供商)
    echo -e "${BLUE}更新嵌入式代理认证配置...${NC}"
    if [ -f "$SCRIPT_DIR/setup_agent_auth.sh" ]; then
        "$SCRIPT_DIR/setup_agent_auth.sh"
    else
        echo -e "${YELLOW}警告: 未找到 setup_agent_auth.sh 脚本${NC}"
    fi
    echo ""

    # 4.6 显示 token 信息
    show_token_info

    # 5. 加载环境变量
    load_environment

    # 6. 检查必要的 API 密钥（使用 provider 专用 key）
    local provider_key_name="${PROVIDER_API_KEY_NAMES[$PROVIDER]:-}"
    local provider_key_value=""
    if [ -n "$provider_key_name" ]; then
        provider_key_value="${!provider_key_name:-}"
    fi
    if [ -z "$provider_key_value" ] && [ "${AI_PROVIDER:-}" != "ollama" ]; then
        echo -e "${YELLOW}警告: 未配置 API Key${NC}"
    fi

    # 7. 选择部署模式
    select_deploy_mode

    # 8. 启动 Docker
    start_docker
}

main "$@"
