#!/bin/bash

###############################################################################
# OpenClaw 一键部署脚本
# 支持 DeepSeek, Gemini, Claude (在线API) 和 Ollama Llama (本地模型)
# 目录结构: 使用 build/reference/, build/runtime/, build/generated/, build/temp/
###############################################################################

# 严格模式
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
RUNTIME_DIR="$BUILD_DIR/runtime"
CONFIG_DIR="$PROJECT_ROOT/config"
TEMPLATES_DIR="$PROJECT_ROOT/templates"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  OpenClaw 一键部署脚本${NC}"
echo -e "${BLUE}  支持 DeepSeek/Gemini/Claude/Ollama${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查运行环境
check_environment() {
    echo -e "${YELLOW}[1/6] 检查运行环境...${NC}"

    # 检查操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if grep -qi microsoft /proc/version 2>/dev/null; then
            echo -e "${GREEN}✓ 检测到 WSL2 环境${NC}"
            IS_WSL=true
        else
            echo -e "${GREEN}✓ 检测到 Linux 环境${NC}"
            IS_WSL=false
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${GREEN}✓ 检测到 macOS 环境${NC}"
        IS_WSL=false
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        echo -e "${YELLOW}! 检测到 Windows，建议在 WSL2 中运行${NC}"
        IS_WSL=true
    else
        echo -e "${RED}✗ 不支持的操作系统: $OSTYPE${NC}"
        exit 1
    fi

    # 检查必要的命令
    MISSING_DEPS=()
    for cmd in git curl; do
        if ! command -v $cmd &> /dev/null; then
            MISSING_DEPS+=($cmd)
        fi
    done

    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        echo -e "${YELLOW}! 需要安装: ${MISSING_DEPS[*]}${NC}"
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y ${MISSING_DEPS[*]}
        elif command -v brew &> /dev/null; then
            brew install ${MISSING_DEPS[*]}
        fi
    fi

    echo -e "${GREEN}✓ 环境检查完成${NC}"
    echo ""
}

# 检查并安装 Docker
check_docker() {
    echo -e "${YELLOW}[2/6] 检查 Docker...${NC}"

    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        echo -e "${GREEN}✓ Docker 已安装: $DOCKER_VERSION${NC}"

        if command -v docker-compose &> /dev/null; then
            echo -e "${GREEN}✓ Docker Compose 已安装${NC}"
        elif docker compose version &> /dev/null 2>&1; then
            echo -e "${GREEN}✓ Docker Compose (v2) 已安装${NC}"
        else
            echo -e "${RED}✗ Docker Compose 未安装${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}! Docker 未安装${NC}"

        # 根据环境提供不同的安装建议
        if [ "$IS_WSL" = true ]; then
            echo ""
            echo "WSL2 中安装 Docker 的两种方法:"
            echo ""
            echo "方法1: 安装 Docker Desktop for Windows (推荐)"
            echo "  1. 下载安装: https://www.docker.com/products/docker-desktop"
            echo "  2. 在 Docker Desktop 设置中启用 WSL2 集成"
            echo "  3. 在 WSL2 中运行: docker ps 验证"
            echo ""
            echo "方法2: 直接在 WSL 中安装 Docker Engine (原生)"
            echo "  运行以下命令:"
            echo "    sudo apt-get update"
            echo "    sudo apt-get install -y docker.io"
            echo "    sudo service docker start"
            echo "    sudo usermod -aG docker \$USER"
            echo "    # 重新登录 WSL 使配置生效"
        else
            echo "请安装 Docker: https://www.docker.com/products/docker-desktop"
        fi

        exit 1
    fi

    # 测试 Docker 运行
    if ! docker ps &> /dev/null; then
        echo -e "${RED}✗ Docker 未运行，请启动 Docker${NC}"

        if [ "$IS_WSL" = true ]; then
            echo ""
            echo "启动 Docker 服务:"
            echo "  sudo service docker start"
            echo "  # 或"
            echo "  sudo dockerd &"
        fi

        exit 1
    fi

    echo -e "${GREEN}✓ Docker 运行正常${NC}"
    echo ""
}

# 初始化 build 目录结构
init_build_structure() {
    echo -e "${YELLOW}[3/6] 初始化 build 目录结构...${NC}"

    # 运行初始化脚本
    if ! bash "$SCRIPT_DIR/init_build_dirs.sh"; then
        echo -e "${RED}✗ build 目录初始化失败${NC}"
        exit 1
    fi

    # 验证 reference 配置已正确复制
    if [ ! -f "$BUILD_DIR/reference/config/openclaw.json" ]; then
        echo -e "${RED}✗ 配置文件复制失败: build/reference/config/openclaw.json 不存在${NC}"
        echo "  请检查磁盘空间和权限"
        exit 1
    fi

    echo -e "${GREEN}✓ build 目录结构初始化完成${NC}"
    echo -e "${GREEN}✓ 配置文件已复制到 build/reference/config/${NC}"
    echo ""
}

# 创建目录结构
create_directories() {
    echo -e "${YELLOW}[4/6] 创建目录结构...${NC}"

    # 运行时目录（在 build/runtime/ 中）
    mkdir -p "$RUNTIME_DIR/secrets"
    mkdir -p "$RUNTIME_DIR/certs"
    mkdir -p "$RUNTIME_DIR/agents/main/agent"
    mkdir -p "$RUNTIME_DIR/agents/main/sessions"
    mkdir -p "$RUNTIME_DIR/skills"
    mkdir -p "$RUNTIME_DIR/devices"
    mkdir -p "$RUNTIME_DIR/credentials"
    mkdir -p "$RUNTIME_DIR/channels"
    mkdir -p "$RUNTIME_DIR/identity"
    mkdir -p "$RUNTIME_DIR/workspace"
    mkdir -p "$RUNTIME_DIR/canvas"
    mkdir -p "$RUNTIME_DIR/env"

    # Docker 目录（在 build/docker/ 中）
    mkdir -p "$BUILD_DIR/docker/input"
    mkdir -p "$BUILD_DIR/docker/workspace"

    # 设置安全的目录权限
    chmod 700 "$RUNTIME_DIR/secrets"
    chmod 700 "$RUNTIME_DIR/certs"

    echo -e "${GREEN}✓ 目录创建完成${NC}"
    echo ""
}

# 配置环境变量（简化版 - 配置创建移至 start_gateway.sh）
configure_environment() {
    echo -e "${YELLOW}[5/6] 检查环境变量配置...${NC}"

    ENV_FILE="$BUILD_DIR/runtime/env/.env"

    if [ -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}! 环境配置文件已存在: $ENV_FILE${NC}"
        echo "  如需更改 AI 提供商，请运行: ./scripts/start_gateway.sh"
    else
        echo -e "${BLUE}环境配置文件将在启动时由 start_gateway.sh 自动创建${NC}"
        echo "  默认将使用 DeepSeek 作为 AI 提供商"
    fi

    echo -e "${GREEN}✓ 环境变量检查完成${NC}"
    echo ""
}

# 安装 Ollama (可选)
install_ollama() {
    echo -e "${YELLOW}[6/6] Ollama 设置 (可选)...${NC}"

    if command -v ollama &> /dev/null; then
        echo -e "${GREEN}✓ Ollama 已安装${NC}"
        OLLAMA_MODELS=${OLLAMA_MODELS:-$HOME/.ollama/models}
        echo "  模型目录: $OLLAMA_MODELS"
    else
        echo -e "${YELLOW}! Ollama 未安装 (可选)${NC}"
        echo "  如需本地 Llama 模型，请运行: $SCRIPT_DIR/setup_ollama.sh"
    fi

    echo ""
}

# 清理 build 目录（保留核心配置）
clean_build() {
    echo -e "${YELLOW}清理 build 目录（保留核心配置）...${NC}"

    if [ ! -d "$BUILD_DIR" ]; then
        echo -e "${GREEN}✓ build 目录不存在，无需清理${NC}"
        return 0
    fi

    # 清理 build 目录下的 backup 文件和目录
    echo "  检查并清理 backup 文件..."
    local backup_patterns=("backup" "backups" "bak" "old")
    local backup_extensions=(".backup" ".bak" ".old" ".orig")
    local found_backup=false

    # 清理 backup 目录
    for pattern in "${backup_patterns[@]}"; do
        if [ -d "$BUILD_DIR/$pattern" ]; then
            rm -rf "$BUILD_DIR/$pattern"
            echo "  ✓ 删除 backup 目录: $pattern"
            found_backup=true
        fi
    done

    # 清理 backup 文件
    for ext in "${backup_extensions[@]}"; do
        while IFS= read -r -d '' file; do
            rm -f "$file"
            echo "  ✓ 删除 backup 文件: $(basename "$file")"
            found_backup=true
        done < <(find "$BUILD_DIR" -maxdepth 2 -type f -name "*$ext" -print0 2>/dev/null)
    done

    # 清理带时间戳的 backup (如 backup_20240101, config.backup.20240101)
    while IFS= read -r -d '' file; do
        rm -rf "$file"
        echo "  ✓ 删除 backup: $(basename "$file")"
        found_backup=true
    done < <(find "$BUILD_DIR" -maxdepth 2 \( -type d -o -type f \) \( -name "*backup*[0-9]*" -o -name "*[0-9]*.backup*" -o -name "*bak*[0-9]*" \) -print0 2>/dev/null)

    if [ "$found_backup" = false ]; then
        echo "  ✓ 未发现 backup 文件"
    fi

    # 创建临时备份目录
    BACKUP_DIR=$(mktemp -d)
    echo "  创建临时备份: $BACKUP_DIR"

    # 备份核心配置（必须保留）
    local backup_items=("runtime/secrets" "runtime/env" "runtime/credentials" "runtime/certs")
    for item in "${backup_items[@]}"; do
        if [ -e "$BUILD_DIR/$item" ]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$item")"
            cp -r "$BUILD_DIR/$item" "$BACKUP_DIR/$item"
            echo "  ✓ 备份: $item"
        fi
    done

    # 清理需要重新生成的目录
    echo "  清理运行时数据..."
    local clean_items=(
        "runtime/agents"
        "runtime/devices"
        "runtime/channels"
        "runtime/identity"
        "runtime/canvas"
        "runtime/skills"
        "runtime/workspace"
        "generated"
        "temp"
        "reference"
        "docker/data"
        "docker/containers"
        "docker/volumes"
        "templates"
        "tools"
    )

    for item in "${clean_items[@]}"; do
        if [ -e "$BUILD_DIR/$item" ]; then
            rm -rf "$BUILD_DIR/$item"
            echo "  ✓ 清理: $item"
        fi
    done

    # 重新初始化目录结构
    echo "  重新初始化目录结构..."
    bash "$SCRIPT_DIR/init_build_dirs.sh" > /dev/null 2>&1

    # 恢复备份的核心配置
    echo "  恢复核心配置..."
    for item in "${backup_items[@]}"; do
        if [ -e "$BACKUP_DIR/$item" ]; then
            mkdir -p "$BUILD_DIR/$(dirname "$item")"
            cp -r "$BACKUP_DIR/$item" "$BUILD_DIR/$item"
            echo "  ✓ 恢复: $item"
        fi
    done

    # 清理临时备份
    rm -rf "$BACKUP_DIR"

    echo -e "${GREEN}✓ 清理完成（核心配置已保留）${NC}"
    echo ""
}

# 完全清理（distclean）
distclean_build() {
    echo -e "${YELLOW}完全清理 build 目录...${NC}"

    if [ ! -d "$BUILD_DIR" ]; then
        echo -e "${GREEN}✓ build 目录不存在，无需清理${NC}"
    else
        # 直接删除build目录
        echo "  正在删除: $BUILD_DIR/"
        rm -rf "$BUILD_DIR"
        echo -e "${GREEN}✓ 已删除 build 目录${NC}"
    fi

    echo -e "${GREEN}✓ 完全清理完成${NC}"
    echo ""
}

# 显示获取 Gateway Token 的命令建议
show_token_retrieval_help() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Gateway Token 获取指南${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "${YELLOW}如需查看 Gateway Token 值，可使用以下命令:${NC}"
    echo ""
    echo "  方法1 - 从 secrets 文件获取:"
    echo "    cat $BUILD_DIR/runtime/secrets/gateway_token"
    echo ""
    echo "  方法2 - 从环境变量文件获取:"
    echo "    grep OPENCLAW_GATEWAY_TOKEN $BUILD_DIR/runtime/env/.env"
    echo ""
    echo "  方法3 - 检查 token 状态:"
    echo "    $SCRIPT_DIR/fix_token_mismatch.sh --check"
    echo ""
    echo -e "${YELLOW}注意: 请妥善保管 token，不要分享给他人${NC}"
    echo ""
}

# 显示目录结构说明
show_directory_structure() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  目录结构说明${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo "build/"
    echo "├── reference/    # 从仓库引用（只读，不修改）"
    echo "│   └── config/ # 配置模板"
    echo "│"
    echo "├── runtime/     # 运行时生成/修改的文件（持久化）"
    echo "│   ├── agents/main/    # Agent 配置和会话"
    echo "│   ├── skills/         # 用户自定义技能"
    echo "│   ├── devices/       # 配对设备信息"
    echo "│   ├── credentials/   # 凭证信息"
    echo "│   ├── channels/      # 通道配置"
    echo "│   ├── identity/      # 身份信息"
    echo "│   ├── certs/         # SSL 证书"
    echo "│   ├── secrets/       # 敏感信息"
    echo "│   ├── env/           # 环境变量"
    echo "│   ├── workspace/     # 用户工作空间"
    echo "│   └── canvas/        # Canvas 数据"
    echo "│"
    echo "├── generated/   # 构建时生成的文件"
    echo "│   └── logs/    # 日志"
    echo "│"
    echo "└── temp/       # 临时文件（可删除）"
    echo "    ├── tmp/    # 临时目录"
    echo "    └── cache/  # 缓存目录"
    echo ""
}

# 显示用法信息
show_usage() {
    echo "用法: $0 [command]"
    echo ""
    echo "命令:"
    echo "  (无)      执行完整的一键部署流程"
    echo "  start     启动 Gateway"
    echo "  clean     清理运行时数据，保留核心配置（API Keys, 环境变量等）"
    echo "  distclean 完全清理，删除所有构建产物（无需确认）"
    echo ""
    echo "示例:"
    echo "  $0              # 执行一键部署"
    echo "  $0 start        # 启动 Gateway"
    echo "  $0 clean        # 清理并重新初始化（保留配置）"
    echo "  $0 distclean    # 完全清理（恢复原始状态）"
}

# 主函数
main() {
    # 如果传入了命令行参数，按参数执行
    if [ $# -gt 0 ]; then
        case "$1" in
            start)
                echo -e "${BLUE}启动 Gateway...${NC}"
                "$SCRIPT_DIR/start_gateway.sh"
                exit 0
                ;;
            clean)
                clean_build
                echo -e "${BLUE}重新初始化目录结构...${NC}"
                bash "$SCRIPT_DIR/init_build_dirs.sh"
                echo ""
                echo -e "${GREEN}清理完成！您可以重新运行部署:${NC}"
                echo "  $0"
                exit 0
                ;;
            distclean)
                distclean_build
                echo ""
                echo -e "${GREEN}完全清理完成！项目已恢复到原始状态。${NC}"
                echo "  如需重新部署，请运行: $0"
                exit 0
                ;;
            help|--help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知命令 '$1'${NC}"
                show_usage
                exit 1
                ;;
        esac
    fi

    # 执行环境检查和配置
    check_environment
    check_docker
    init_build_structure
    create_directories
    configure_environment
    install_ollama

    # 显示目录结构说明
    show_directory_structure

    echo -e "${BLUE}============================================${NC}"
    echo -e "${GREEN}  部署准备完成，启动 Gateway!${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""

    # 显示获取 token 的命令建议
    show_token_retrieval_help

    echo -e "${BLUE}启动 Gateway (将引导您配置 AI 提供商和 API 密钥)...${NC}"
    echo ""
    "$SCRIPT_DIR/start_gateway.sh"
}

main "$@"
