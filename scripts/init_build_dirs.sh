#!/bin/bash
# ==============================================================================
# OpenClaw - Build 目录初始化脚本
#
# 此脚本在首次运行时创建所有必需的目录
# 目录结构按照"是否修改"进行分类：
#   - reference: 从仓库引用（不修改）
#   - runtime: 运行时生成/修改的文件
#   - generated: 构建时生成的文件
#   - temp: 临时文件
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"

echo "初始化 OpenClaw build 目录..."

# 创建 build 目录（如果不存在）
mkdir -p "$BUILD_DIR"

# ==============================================================================
# 1. reference/ - 从仓库引用（只读，不修改）
#    这些文件来自仓库的 config/ 目录，但不在运行时修改
#    复制到 build/reference/ 以确保原始仓库文件不被修改
# ==============================================================================
mkdir -p "$BUILD_DIR/reference/config"

# 复制配置文件到 reference 目录（保持目录结构）
copy_config_to_reference() {
    echo "  复制配置文件到 build/reference/config/..."

    # 使用 rsync 或 cp -r 复制，排除运行时生成的文件
    if command -v rsync &> /dev/null; then
        rsync -a --exclude='agents/main/agent' --exclude='agents/main/sessions' \
              "$PROJECT_ROOT/config/" "$BUILD_DIR/reference/config/"
    else
        # 使用 cp -r 并手动排除
        # 先复制主要配置文件
        cp -r "$PROJECT_ROOT/config/"* "$BUILD_DIR/reference/config/" 2>/dev/null || true

        # 移除可能存在的符号链接（将在 runtime 中创建）
        rm -f "$BUILD_DIR/reference/config/agents/main/agent" 2>/dev/null || true
        rm -f "$BUILD_DIR/reference/config/agents/main/sessions" 2>/dev/null || true
    fi

    echo "  ✓ 配置文件已复制到 build/reference/config/"
}

copy_config_to_reference

# ==============================================================================
# 2. runtime/ - 运行时生成/修改的文件
#    这些文件在运行时会发生变化，需要持久化
# ==============================================================================

# Agent 运行时配置
mkdir -p "$BUILD_DIR/runtime/agents/main/agent"
mkdir -p "$BUILD_DIR/runtime/agents/main/sessions"

# 用户数据
mkdir -p "$BUILD_DIR/runtime/skills"         # 用户自定义技能
mkdir -p "$BUILD_DIR/runtime/devices"        # 配对设备信息
mkdir -p "$BUILD_DIR/runtime/credentials"    # 凭证信息
mkdir -p "$BUILD_DIR/runtime/channels"       # 通道配置
mkdir -p "$BUILD_DIR/runtime/identity"       # 身份信息

# 运行时配置
mkdir -p "$BUILD_DIR/runtime/certs"          # SSL 证书
mkdir -p "$BUILD_DIR/runtime/secrets"        # 敏感信息
mkdir -p "$BUILD_DIR/runtime/env"            # 环境变量文件

# 用户工作空间
mkdir -p "$BUILD_DIR/runtime/workspace"     # 用户工作空间
mkdir -p "$BUILD_DIR/runtime/canvas"         # Canvas 数据

# ==============================================================================
# 3. generated/ - 构建时生成的文件
#    这些文件在项目构建或首次部署时生成
# ==============================================================================
mkdir -p "$BUILD_DIR/generated/logs"         # 日志目录

# ==============================================================================
# 4. temp/ - 临时文件
#    这些文件可以随时删除，不影响运行
# ==============================================================================
mkdir -p "$BUILD_DIR/temp/tmp"
mkdir -p "$BUILD_DIR/temp/cache"

# ==============================================================================
# 5. docker/ - Docker 相关目录
# ==============================================================================
mkdir -p "$BUILD_DIR/docker/input"           # Docker 输入文件
mkdir -p "$BUILD_DIR/docker/workspace"       # Docker 工作空间
mkdir -p "$BUILD_DIR/docker/data"            # Docker 数据卷
mkdir -p "$BUILD_DIR/docker/containers"      # Docker 容器数据
mkdir -p "$BUILD_DIR/docker/volumes"         # Docker 命名卷

# ==============================================================================
# 6. templates/ - 模板目录（可由用户扩展）
# ==============================================================================
mkdir -p "$BUILD_DIR/templates"

# ==============================================================================
# 7. tools/ - 工具目录
# ==============================================================================
mkdir -p "$BUILD_DIR/tools"

echo "Build 目录初始化完成: $BUILD_DIR"
echo ""
echo "目录结构说明:"
echo "  build/"
echo "  ├── reference/        # 从仓库引用（只读，不修改）"
echo "  │   └── config/       # 配置模板"
echo "  │"
echo "  ├── runtime/          # 运行时生成/修改的文件（持久化）"
echo "  │   ├── agents/main/  # Agent 配置和会话"
echo "  │   ├── skills/       # 用户自定义技能"
echo "  │   ├── devices/      # 配对设备信息"
echo "  │   ├── credentials/  # 凭证信息"
echo "  │   ├── channels/    # 通道配置"
echo "  │   ├── identity/    # 身份信息"
echo "  │   ├── certs/       # SSL 证书"
echo "  │   ├── secrets/     # 敏感信息"
echo "  │   ├── env/         # 环境变量"
echo "  │   ├── workspace/   # 用户工作空间"
echo "  │   └── canvas/      # Canvas 数据"
echo "  │"
echo "  ├── generated/        # 构建时生成的文件"
echo "  │   └── logs/         # 日志"
echo "  │"
echo "  ├── temp/             # 临时文件（可删除）"
echo "  │   ├── tmp/          # 临时目录"
echo "  │   └── cache/        # 缓存目录"
echo "  │"
echo "  ├── docker/           # Docker 相关"
echo "  │   ├── input/        # 输入文件"
echo "  │   ├── workspace/    # 工作空间"
echo "  │   ├── data/         # 数据"
echo "  │   ├── containers/   # 容器数据"
echo "  │   └── volumes/      # 命名卷"
echo "  │"
echo "  ├── templates/        # 模板目录"
echo "  └── tools/            # 工具目录"
echo ""
echo "文件分类说明:"
echo "  - reference/: 从仓库 config/ 引用，不修改"
echo "  - runtime/:   运行时生成/修改，需要持久化"
echo "  - generated/: 构建时生成"
echo "  - temp/:      临时文件，可随时删除"
echo ""
echo "所有初始化完成!"
echo ""
echo "重要提示:"
echo "  - 原始配置文件已复制到 build/reference/config/（只读）"
echo "  - 运行时数据将写入 build/runtime/（可写）"
echo "  - Docker环境使用直接挂载，不依赖符号链接"
