#!/bin/bash

###############################################################################
# OpenClaw Gateway 生产环境部署脚本
# 功能: 安全加固、Docker Secrets 配置、HTTPS 设置
# 目录结构: 使用 build/reference/, build/runtime/, build/generated/, build/temp/
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

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  OpenClaw Gateway 生产环境部署${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查 Docker 和 Docker Compose
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: Docker 未安装${NC}"
        exit 1
    fi

    if ! docker compose version &> /dev/null 2>&1; then
        echo -e "${RED}错误: Docker Compose V2 未安装${NC}"
        echo "生产环境需要 Docker Compose V2+ 支持 Docker Secrets"
        exit 1
    fi

    echo -e "${GREEN}✓ Docker 环境检查通过${NC}"
}

# 初始化 build 目录结构
init_build_structure() {
    echo -e "${BLUE}初始化 build 目录结构...${NC}"

    # 运行初始化脚本
    bash "$SCRIPT_DIR/init_build_dirs.sh"

    echo -e "${GREEN}✓ build 目录结构初始化完成${NC}"
}

# 创建必要的运行时目录（指向 build/runtime/）
create_runtime_directories() {
    echo -e "${BLUE}创建必要的运行时目录...${NC}"

    RUNTIME_DIR="$BUILD_DIR/runtime"

    local dirs=(
        "$RUNTIME_DIR/secrets"        # Gateway Token
        "$RUNTIME_DIR/certs"          # SSL 证书
        "$RUNTIME_DIR/agents/main/agent"  # Agent 配置
        "$RUNTIME_DIR/agents/main/sessions"  # Agent 会话
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "  创建: $dir"
            mkdir -p "$dir"
        fi
    done

    # 设置安全的权限
    chmod 700 "$RUNTIME_DIR/secrets"
    chmod 700 "$RUNTIME_DIR/certs"

    echo -e "${GREEN}✓ 运行时目录创建完成${NC}"
}

# 生成或验证 Gateway Token
setup_gateway_token() {
    echo -e "${BLUE}配置 Gateway Token...${NC}"

    local secrets_file="$BUILD_DIR/runtime/secrets/gateway_token"

    if [ -f "$secrets_file" ] && [ -s "$secrets_file" ]; then
        echo -e "${GREEN}✓ 已存在 Gateway Token${NC}"
        local token_preview=$(head -c 16 "$secrets_file")
        echo "  Token: ${token_preview}..."
    else
        echo "  生成新的 Gateway Token..."
        openssl rand -hex 32 > "$secrets_file"
        chmod 600 "$secrets_file"
        local token_preview=$(head -c 16 "$secrets_file")
        echo -e "${GREEN}✓ 已生成 Gateway Token: ${token_preview}...${NC}"
    fi

    # 同步到 build/runtime/env/.env（用于开发环境回退）
    local env_file="$BUILD_DIR/runtime/env/.env"
    mkdir -p "$(dirname "$env_file")"
    local token=$(cat "$secrets_file" | tr -d '\n\r')
    if [ -f "$env_file" ]; then
        if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null; then
            sed -i "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$token|" "$env_file"
        else
            echo "OPENCLAW_GATEWAY_TOKEN=$token" >> "$env_file"
        fi
    else
        echo "OPENCLAW_GATEWAY_TOKEN=$token" > "$env_file"
    fi
}

# 配置 SSL/TLS 证书
setup_ssl_certificates() {
    echo -e "${BLUE}检查 SSL/TLS 证书...${NC}"

    local certs_dir="$BUILD_DIR/runtime/certs"
    local key_file="$certs_dir/server.key"
    local cert_file="$certs_dir/server.crt"

    if [ -f "$key_file" ] && [ -f "$cert_file" ]; then
        echo -e "${GREEN}✓ 已存在 SSL 证书${NC}"
        echo "  证书文件: $cert_file"
        echo "  密钥文件: $key_file"
        echo ""
        echo -e "${YELLOW}提示: 如需使用自签名证书，请确保证书有效期${NC}"
        openssl x509 -in "$cert_file" -noout -dates 2>/dev/null || true
    else
        echo -e "${YELLOW}未找到 SSL 证书，生成自签名证书...${NC}"
        echo "  注意: 自签名证书仅用于测试，生产环境建议使用受信任的证书"

        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -subj "/C=CN/ST=State/L=City/O=OpenClaw/CN=localhost" \
            2>/dev/null

        chmod 600 "$key_file"
        chmod 644 "$cert_file"

        echo -e "${GREEN}✓ 已生成自签名证书${NC}"
        echo "  证书有效期: 365 天"
        echo -e "${YELLOW}警告: 浏览器会显示证书不受信任，这是正常的${NC}"
    fi
}

# 验证配置文件
validate_configs() {
    echo -e "${BLUE}验证配置文件...${NC}"

    local config_file="$PROJECT_ROOT/config/openclaw.json"
    local models_file="$BUILD_DIR/runtime/agents/main/agent/models.json"

    # 检查主配置文件
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}错误: 主配置文件不存在: $config_file${NC}"
        echo "请运行: ./scripts/generate_openclaw_config.sh"
        exit 1
    fi

    # 验证 JSON 格式
    if ! python3 -c "import json; json.load(open('$config_file'))" 2>/dev/null; then
        echo -e "${RED}错误: 配置文件 JSON 格式无效: $config_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ 主配置文件验证通过${NC}"

    # 检查 models.json（从 config/ 复制到 runtime/）
    if [ ! -f "$models_file" ]; then
        # 尝试从 config/agents/main/agent/ 复制
        local source_models="$PROJECT_ROOT/config/agents/main/agent/models.json"
        if [ -f "$source_models" ]; then
            echo "  从模板复制 models.json..."
            cp "$source_models" "$models_file"
        else
            echo -e "${YELLOW}警告: models.json 不存在，将使用默认配置${NC}"
            # 创建默认的 models.json
            cat > "$models_file" << 'EOF'
{
  "providers": {
    "deepseek": {
      "baseUrl": "https://api.deepseek.com/v1",
      "apiKey": "",
      "api": "openai-completions",
      "models": [
        {
          "id": "deepseek-chat",
          "name": "DeepSeek Chat",
          "contextWindow": 64000,
          "maxTokens": 8192,
          "reasoning": false,
          "input": ["text"],
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }
      ]
    }
  }
}
EOF
            echo -e "${YELLOW}请编辑 $models_file 配置您的 API Key${NC}"
        fi
    fi

    # 检查 API Key 是否配置
    if grep -q '"apiKey": ""' "$models_file" 2>/dev/null; then
        echo -e "${YELLOW}警告: models.json 中的 API Key 为空${NC}"
        echo "请编辑 $models_file 配置您的 API Key"
    fi
}

# 安全加固检查
security_hardening() {
    echo -e "${BLUE}执行安全加固检查...${NC}"

    # 检查文件权限
    local secrets_file="$BUILD_DIR/runtime/secrets/gateway_token"
    if [ -f "$secrets_file" ]; then
        local perms=$(stat -c %a "$secrets_file" 2>/dev/null || stat -f %Lp "$secrets_file" 2>/dev/null)
        if [ "$perms" != "600" ]; then
            echo -e "${YELLOW}修复 secrets 文件权限...${NC}"
            chmod 600 "$secrets_file"
        fi
    fi

    # 检查 .env 文件是否存在敏感信息泄露风险
    local env_file="$BUILD_DIR/runtime/env/.env"
    if [ -f "$env_file" ]; then
        if grep -q "sk-" "$env_file" 2>/dev/null; then
            echo -e "${YELLOW}警告: .env 文件可能包含 API Keys${NC}"
            echo "生产环境建议使用 Docker Secrets 而非 .env 文件"
        fi
    fi

    echo -e "${GREEN}✓ 安全加固检查完成${NC}"
}

# 启动生产环境服务
start_production() {
    echo -e "${BLUE}启动生产环境服务...${NC}"

    cd "$PROJECT_ROOT/docker"

    # 清理现有容器
    echo "  清理现有容器..."
    docker compose -f docker-compose.yml -f docker-compose.prod.yml down 2>/dev/null || true

    # 构建生产镜像
    echo "  构建生产镜像..."
    docker compose -f docker-compose.yml -f docker-compose.prod.yml build

    # 启动服务
    echo "  启动服务..."
    docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

    # 等待服务启动
    echo "  等待服务启动..."
    sleep 5

    # 检查服务状态
    if docker compose -f docker-compose.yml -f docker-compose.prod.yml ps | grep -q "openclaw-gateway.*Up"; then
        echo -e "${GREEN}✓ 生产环境服务已启动${NC}"
        echo ""
        echo "访问地址:"
        echo "  - Web UI: http://localhost:18789"
        echo "  - WebSocket: ws://localhost:18789"
        echo ""
        echo "安全特性:"
        echo "  ✓ Docker Secrets 保护 Gateway Token"
        echo "  ✓ 只读根文件系统"
        echo "  ✓ 最小化 Linux 能力"
        echo "  ✓ 命名卷持久化数据"
        echo ""
        echo "查看日志:"
        echo "  docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f"
    else
        echo -e "${RED}✗ 服务启动失败${NC}"
        docker compose -f docker-compose.yml -f docker-compose.prod.yml logs
        exit 1
    fi
}

# 显示部署信息
show_deployment_info() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  部署信息${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    local token_file="$BUILD_DIR/runtime/secrets/gateway_token"
    if [ -f "$token_file" ]; then
        local token=$(cat "$token_file" | tr -d '\n\r')
        echo "Gateway Token: ${token:0:16}...${token: -8}"
    fi

    echo ""
    echo "目录结构:"
    echo "  - build/reference/    # 从仓库引用（只读）"
    echo "  - build/runtime/     # 运行时生成/修改"
    echo "  - build/generated/  # 构建时生成"
    echo "  - build/temp/       # 临时文件"
    echo ""
    echo "配置文件位置:"
    echo "  - 主配置: $PROJECT_ROOT/config/openclaw.json"
    echo "  - 模型配置: $BUILD_DIR/runtime/agents/main/agent/models.json"
    echo "  - Secrets: $BUILD_DIR/runtime/secrets/"
    echo "  - 证书: $BUILD_DIR/runtime/certs/"
    echo "  - 环境变量: $BUILD_DIR/runtime/env/.env"
    echo ""

    echo "常用命令:"
    echo "  查看日志: docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml logs -f"
    echo "  停止服务: docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml down"
    echo "  重启服务: docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml restart"
    echo ""

    echo -e "${YELLOW}安全提示:${NC}"
    echo "  1. 定期轮换 Gateway Token: ./scripts/rotate_token.sh"
    echo "  2. 监控日志异常: docker compose logs -f | grep -i error"
    echo "  3. 备份配置文件: cp -r build/runtime/ runtime.backup.$(date +%Y%m%d)/"
    echo "  4. 使用 HTTPS 生产环境建议配置受信任的 SSL 证书"
    echo ""
}

# 主函数
main() {
    check_docker
    init_build_structure
    create_runtime_directories
    setup_gateway_token
    setup_ssl_certificates
    validate_configs
    security_hardening
    start_production
    show_deployment_info
}

main "$@"
