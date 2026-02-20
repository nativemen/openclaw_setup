#!/bin/bash

###############################################################################
# OpenClaw Gateway 安全监控脚本
# 功能: 日志审计、异常检测、安全事件告警
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
LOG_DIR="$PROJECT_ROOT/config/logs"
ALERT_LOG="$LOG_DIR/security_alerts.log"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 获取当前时间
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 记录告警
log_alert() {
    local level="$1"
    local message="$2"
    local ts=$(timestamp)
    echo "[$ts] [$level] $message" >> "$ALERT_LOG"
    echo -e "[$ts] [$level] $message"
}

# 检查 Docker 容器状态
check_container_status() {
    local container_name="openclaw-gateway"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_alert "CRITICAL" "容器 $container_name 未运行"
        return 1
    fi

    # 检查容器重启次数
    local restart_count=$(docker inspect --format='{{.RestartCount}}' "$container_name" 2>/dev/null || echo "0")
    if [ "$restart_count" -gt 5 ]; then
        log_alert "WARNING" "容器 $container_name 重启次数过多: $restart_count"
    fi

    return 0
}

# 监控日志异常
monitor_logs() {
    local compose_file="$PROJECT_ROOT/docker/docker-compose.yml"
    local prod_file="$PROJECT_ROOT/docker/docker-compose.prod.yml"

    # 检查是否使用生产配置
    local compose_args=""
    if [ -f "$prod_file" ]; then
        compose_args="-f $compose_file -f $prod_file"
    else
        compose_args="-f $compose_file"
    fi

    # 获取最近日志并检查异常
    local recent_logs=$(docker compose $compose_args logs --tail=100 2>/dev/null || echo "")

    # 检查各类异常
    if echo "$recent_logs" | grep -qi "EROFS.*read-only file system"; then
        log_alert "ERROR" "检测到只读文件系统错误 (EROFS)"
        echo -e "${YELLOW}建议: 检查卷挂载配置，确保使用命名卷而非只读挂载${NC}"
    fi

    if echo "$recent_logs" | grep -qi "authentication failed\|unauthorized\|401"; then
        log_alert "WARNING" "检测到认证失败事件"
    fi

    if echo "$recent_logs" | grep -qi "connection refused\|ECONNREFUSED"; then
        log_alert "WARNING" "检测到连接被拒绝错误"
    fi

    if echo "$recent_logs" | grep -qi "rate limit\|too many requests\|429"; then
        log_alert "WARNING" "检测到 API 速率限制"
    fi

    # 检查 WebSocket 断开连接
    local ws_disconnects=$(echo "$recent_logs" | grep -c "webchat disconnected" || echo "0")
    if [ "$ws_disconnects" -gt 10 ]; then
        log_alert "WARNING" "WebSocket 断开连接次数过多: $ws_disconnects"
    fi
}

# 检查文件权限
check_file_permissions() {
    local issues=0

    # 检查 secrets 目录权限
    local secrets_dir="$PROJECT_ROOT/build/runtime/secrets"
    if [ -d "$secrets_dir" ]; then
        local dir_perms=$(stat -c %a "$secrets_dir" 2>/dev/null || stat -f %Lp "$secrets_dir" 2>/dev/null)
        if [ "$dir_perms" != "700" ]; then
            log_alert "WARNING" "secrets 目录权限过于开放: $dir_perms (应为 700)"
            ((issues++))
        fi
    fi

    # 检查 gateway_token 文件权限
    local token_file="$PROJECT_ROOT/build/runtime/secrets/gateway_token"
    if [ -f "$token_file" ]; then
        local file_perms=$(stat -c %a "$token_file" 2>/dev/null || stat -f %Lp "$token_file" 2>/dev/null)
        if [ "$file_perms" != "600" ]; then
            log_alert "WARNING" "gateway_token 文件权限过于开放: $file_perms (应为 600)"
            ((issues++))
        fi
    fi

    # 检查 SSL 证书权限
    local key_file="$PROJECT_ROOT/build/runtime/certs/server.key"
    if [ -f "$key_file" ]; then
        local key_perms=$(stat -c %a "$key_file" 2>/dev/null || stat -f %Lp "$key_file" 2>/dev/null)
        if [ "$key_perms" != "600" ]; then
            log_alert "WARNING" "SSL 私钥权限过于开放: $key_perms (应为 600)"
            ((issues++))
        fi
    fi

    if [ $issues -eq 0 ]; then
        log_alert "INFO" "文件权限检查通过"
    fi
}

# 检查 API Key 安全
check_api_key_security() {
    local models_file="$PROJECT_ROOT/build/runtime/agents/main/agent/models.json"

    if [ ! -f "$models_file" ]; then
        log_alert "WARNING" "models.json 配置文件不存在"
        return
    fi

    # 检查 API Key 是否为空
    if grep -q '"apiKey": ""' "$models_file"; then
        log_alert "WARNING" "models.json 中的 API Key 为空，服务可能无法正常工作"
    fi

    # 检查 API Key 是否使用环境变量（推荐）
    if grep -q '"apiKey": "${' "$models_file"; then
        log_alert "INFO" "API Key 使用环境变量，符合安全最佳实践"
    fi

    # 检查是否使用了硬编码的 API Key（潜在风险）
    if grep -q '"apiKey": "sk-' "$models_file"; then
        log_alert "WARNING" "models.json 中包含硬编码的 API Key，建议改用环境变量"
    fi
}

# 检查网络连接
check_network_connectivity() {
    # 检查网关端口
    if ! nc -z localhost 18789 2>/dev/null; then
        log_alert "ERROR" "无法连接到网关端口 18789"
        return 1
    fi

    log_alert "INFO" "网关端口 18789 连接正常"
    return 0
}

# 生成安全报告
generate_security_report() {
    local report_file="$LOG_DIR/security_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "OpenClaw Gateway 安全报告"
        echo "生成时间: $(timestamp)"
        echo "=========================================="
        echo ""

        echo "1. 容器状态:"
        docker ps --filter "name=openclaw-gateway" --format "  名称: {{.Names}}\n  状态: {{.Status}}\n  端口: {{.Ports}}" 2>/dev/null || echo "  容器未运行"
        echo ""

        echo "2. 镜像信息:"
        docker images --format "  {{.Repository}}:{{.Tag}} ({{.Size}})" | grep openclaw 2>/dev/null || echo "  未找到镜像"
        echo ""

        echo "3. 卷挂载:"
        docker volume ls --format "  {{.Name}}" | grep openclaw 2>/dev/null || echo "  未找到卷"
        echo ""

        echo "4. 最近告警:"
        if [ -f "$ALERT_LOG" ]; then
            tail -20 "$ALERT_LOG"
        else
            echo "  无告警记录"
        fi
        echo ""

        echo "5. 文件权限:"
        ls -la "$PROJECT_ROOT/build/runtime/secrets/" 2>/dev/null || echo "  无法读取 secrets 目录"
        ls -la "$PROJECT_ROOT/build/runtime/certs/" 2>/dev/null || echo "  无法读取 certs 目录"
        echo ""

        echo "6. 网络连接:"
        ss -tlnp | grep 18789 2>/dev/null || netstat -tlnp 2>/dev/null | grep 18789 || echo "  端口 18789 未监听"
        echo ""

    } > "$report_file"

    echo -e "${GREEN}安全报告已生成: $report_file${NC}"
}

# 实时日志监控
monitor_realtime() {
    echo -e "${BLUE}启动实时日志监控 (按 Ctrl+C 退出)...${NC}"
    echo ""

    local compose_file="$PROJECT_ROOT/docker/docker-compose.yml"
    local prod_file="$PROJECT_ROOT/docker/docker-compose.prod.yml"

    local compose_args=""
    if [ -f "$prod_file" ]; then
        compose_args="-f $compose_file -f $prod_file"
    else
        compose_args="-f $compose_file"
    fi

    # 使用 grep 过滤关键日志
    docker compose $compose_args logs -f 2>&1 | while read -r line; do
        # 高亮显示错误和警告
        if echo "$line" | grep -qi "error\|failed\|critical"; then
            echo -e "${RED}$line${NC}"
            log_alert "ERROR" "$(echo "$line" | tail -c 200)"
        elif echo "$line" | grep -qi "warning\|warn"; then
            echo -e "${YELLOW}$line${NC}"
            log_alert "WARNING" "$(echo "$line" | tail -c 200)"
        elif echo "$line" | grep -qi "authentication\|login\|token"; then
            echo -e "${BLUE}$line${NC}"
        else
            echo "$line"
        fi
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
OpenClaw Gateway 安全监控脚本

用法: ./scripts/security_monitor.sh [命令]

命令:
  check       执行一次性安全检查
  monitor     启动实时日志监控
  report      生成安全报告
  help        显示帮助信息

示例:
  ./scripts/security_monitor.sh check     # 执行安全检查
  ./scripts/security_monitor.sh monitor   # 实时监控日志
  ./scripts/security_monitor.sh report    # 生成安全报告

EOF
}

# 主函数
main() {
    local command="${1:-check}"

    case "$command" in
        check)
            echo -e "${BLUE}执行安全检查...${NC}"
            check_container_status
            check_file_permissions
            check_api_key_security
            check_network_connectivity
            monitor_logs
            echo -e "${GREEN}安全检查完成${NC}"
            ;;
        monitor)
            monitor_realtime
            ;;
        report)
            generate_security_report
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}未知命令: $command${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
