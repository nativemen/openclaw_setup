#!/bin/bash

###############################################################################
# OpenClaw HTTPS 配置脚本
# 为生产环境启用 HTTPS
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
CONFIG_FILE="$PROJECT_ROOT/config/openclaw.json"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  OpenClaw HTTPS 配置工具${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}错误: 配置文件不存在: $CONFIG_FILE${NC}"
    exit 1
fi

# 生成自签名证书
generate_self_signed_cert() {
    local cert_dir="$PROJECT_ROOT/build/runtime/certs"

    mkdir -p "$cert_dir"

    echo "生成自签名证书..."

    # 生成私钥
    openssl genrsa -out "$cert_dir/server.key" 2048 2>/dev/null

    # 生成证书
    openssl req -new -x509 -key "$cert_dir/server.key" -out "$cert_dir/server.crt" -days 365 \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=OpenClaw/CN=localhost" 2>/dev/null

    echo -e "${GREEN}✓ 证书已生成${NC}"
    echo "  私钥: $cert_dir/server.key"
    echo "  证书: $cert_dir/server.crt"

    echo "$cert_dir/server.crt" "$cert_dir/server.key"
}

# 更新配置文件
update_config() {
    local cert_path="$1"
    local key_path="$2"

    # 使用 jq 更新 JSON（如果可用）
    if command -v jq &> /dev/null; then
        jq ".security.https.enabled = true | .security.https.certPath = \"$cert_path\" | .security.https.keyPath = \"$key_path\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        # 手动更新（基本替换）
        sed -i "s/\"enabled\": false/\"enabled\": true/" "$CONFIG_FILE"
        sed -i "s/\"certPath\": \"\"/\"certPath\": \"$cert_path\"/" "$CONFIG_FILE"
        sed -i "s/\"keyPath\": \"\"/\"keyPath\": \"$key_path\"/" "$CONFIG_FILE"
    fi

    echo -e "${GREEN}✓ 配置文件已更新${NC}"
}

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示帮助信息"
    echo "  -g, --generate      生成自签名证书并启用 HTTPS"
    echo "  -c, --custom        使用自定义证书"
    echo "  -d, --disable      禁用 HTTPS"
    echo ""
    echo "示例:"
    echo "  $0 --generate       # 生成自签名证书并启用"
    echo "  $0 --custom /path/to/cert.crt /path/to/key.key  # 使用自定义证书"
    echo "  $0 --disable        # 禁用 HTTPS"
    echo ""
    echo "注意: 自签名证书仅用于测试,生产环境请使用正式证书"
}

# 禁用 HTTPS
disable_https() {
    if command -v jq &> /dev/null; then
        jq ".security.https.enabled = false" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        sed -i "s/\"enabled\": true/\"enabled\": false/" "$CONFIG_FILE"
    fi
    echo -e "${GREEN}✓ HTTPS 已禁用${NC}"
}

# 主函数
main() {
    local action=""
    local cert_path=""
    local key_path=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -g|--generate)
                action="generate"
                shift
                ;;
            -c|--custom)
                action="custom"
                cert_path="$2"
                key_path="$3"
                shift 3
                ;;
            -d|--disable)
                action="disable"
                shift
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    if [ -z "$action" ]; then
        show_help
        exit 0
    fi

    case "$action" in
        generate)
            cert_path=$(generate_self_signed_cert | head -1)
            key_path=$(generate_self_signed_cert | tail -1)
            update_config "$cert_path" "$key_path"
            ;;
        custom)
            if [ -z "$cert_path" ] || [ -z "$key_path" ]; then
                echo -e "${RED}错误: 请提供证书和私钥路径${NC}"
                exit 1
            fi
            if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
                echo -e "${RED}错误: 证书或私钥文件不存在${NC}"
                exit 1
            fi
            update_config "$cert_path" "$key_path"
            ;;
        disable)
            disable_https
            ;;
    esac

    echo ""
    echo -e "${GREEN}配置完成!${NC}"
    echo "请重启 Gateway 使配置生效:"
    echo "  cd docker && docker compose restart"
}

main "$@"
