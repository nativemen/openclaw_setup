#!/bin/bash

###############################################################################
# Ollama 本地模型设置脚本
# 用于下载和管理本地 Llama 模型
###############################################################################

# 严格模式
set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Ollama 本地模型设置${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查 Ollama 是否安装
check_ollama() {
    if command -v ollama &> /dev/null; then
        OLLAMA_VERSION=$(ollama --version)
        echo -e "${GREEN}✓ Ollama 已安装: $OLLAMA_VERSION${NC}"
        return 0
    else
        return 1
    fi
}

# 安装 Ollama
install_ollama() {
    echo -e "${YELLOW}正在安装 Ollama...${NC}"

    # 检测操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if grep -qi microsoft /proc/version 2>/dev/null; then
            # WSL2
            echo "检测到 WSL2 环境"
            curl -fsSL https://ollama.com/install.sh | sh
        else
            # Linux
            curl -fsSL https://ollama.com/install.sh | sh
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew install ollama
    else
        echo -e "${RED}不支持的操作系统${NC}"
        echo "请手动安装: https://ollama.com/download"
        exit 1
    fi
}

# 下载模型
download_model() {
    local model=$1

    echo -e "${YELLOW}下载模型: $model${NC}"
    ollama pull $model

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 模型 $model 下载完成${NC}"
    else
        echo -e "${RED}✗ 模型 $model 下载失败${NC}"
        return 1
    fi
}

# 列出可用模型
list_models() {
    echo "可用模型列表:"
    echo ""
    echo "推荐简历生成模型:"
    echo "  - llama3.1:8b    (英文简历推荐，8GB RAM+)"
    echo "  - llama3.1:70b   (更高质量，64GB RAM+)"
    echo ""
    echo "轻量级模型:"
    echo "  - mistral:7b     (轻量快速，6GB RAM+)"
    echo "  - qwen2.5:7b     (中文支持好，8GB RAM+)"
    echo ""
    echo "查看所有模型: ollama list"
}

# 启动 Ollama 服务
start_ollama() {
    echo "启动 Ollama 服务..."

    # 检测是否有 GPU
    if command -v nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓ 检测到 NVIDIA GPU，将使用 GPU 加速${NC}"
        nvidia-smi --query-gpu=name,memory.total --format=csv
    else
        echo -e "${YELLOW}! 未检测到 GPU，将使用 CPU 运行${NC}"
    fi

    # 启动服务
    ollama serve &
    OLLAMA_PID=$!

    # 等待服务启动
    sleep 3

    if ps -p $OLLAMA_PID > /dev/null; then
        echo -e "${GREEN}✓ Ollama 服务已启动 (PID: $OLLAMA_PID)${NC}"
    else
        echo -e "${RED}✗ Ollama 服务启动失败${NC}"
        return 1
    fi
}

# 停止 Ollama 服务
stop_ollama() {
    pkill -f "ollama serve" || true
    echo -e "${GREEN}✓ Ollama 服务已停止${NC}"
}

# 测试模型
test_model() {
    local model=$1

    echo -e "${YELLOW}测试模型: $model${NC}"
    echo "输入 'quit' 退出测试"
    echo ""

    ollama run $model
}

# 主菜单
main() {
    if ! check_ollama; then
        echo -e "${YELLOW}Ollama 未安装${NC}"
        read -p "是否现在安装 Ollama? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_ollama
        else
            exit 0
        fi
    fi

    while true; do
        echo ""
        echo "请选择操作:"
        echo "  1) 下载推荐模型 (llama3.1:8b)"
        echo "  2) 下载大模型 (llama3.1:70b)"
        echo "  3) 下载中文模型 (qwen2.5:7b)"
        echo "  4) 查看所有可用模型"
        echo "  5) 启动 Ollama 服务"
        echo "  6) 停止 Ollama 服务"
        echo "  7) 测试模型对话"
        echo "  8) 退出"
        echo ""
        read -p "请选择 [1-8]: " choice

        case $choice in
            1)
                download_model "llama3.1:8b"
                ;;
            2)
                download_model "llama3.1:70b"
                ;;
            3)
                download_model "qwen2.5:7b"
                ;;
            4)
                ollama list
                ;;
            5)
                start_ollama
                ;;
            6)
                stop_ollama
                ;;
            7)
                echo "当前已下载的模型:"
                ollama list
                read -p "输入要测试的模型名称: " model
                if [ -n "$model" ]; then
                    test_model $model
                fi
                ;;
            8)
                echo "退出"
                exit 0
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    done
}

main "$@"
