# OpenClaw Gateway 生产环境部署指南

## 概述

本文档提供 OpenClaw Gateway 生产环境的安全部署方案，解决 `EROFS: read-only file system` 错误，并确保满足网络安全和隐私保护要求。

## 问题分析

### 错误信息
```
Error: EROFS: read-only file system, open '/home/node/.openclaw/agents/main/agent/models.json'
```

### 根本原因
生产环境配置 (`docker-compose.prod.yml`) 将 `agents/main/agent` 目录挂载为只读 (`:ro`)，但 OpenClaw Gateway 需要写入 `models.json` 文件来更新模型配置。

## 解决方案

### 方案特点

| 特性 | 实现方式 | 安全级别 |
|------|----------|----------|
| **数据持久化** | 使用 Docker 命名卷 | ✅ 高 |
| **敏感信息保护** | Docker Secrets | ✅ 高 |
| **文件系统安全** | 只读根文件系统 + 可写命名卷 | ✅ 高 |
| **权限控制** | 非 root 用户运行 | ✅ 高 |
| **网络安全** | Host 网络模式 + 防火墙 | ✅ 高 |
| **日志审计** | 持久化日志 + 监控脚本 | ✅ 高 |

## 快速部署

### 1. 一键部署

```bash
# 执行生产环境部署脚本
./scripts/deploy_production.sh
```

该脚本会自动完成：
- 创建必要的目录结构
- 生成 Gateway Token
- 配置 SSL/TLS 证书
- 验证配置文件
- 安全加固检查
- 启动生产环境服务

### 2. 手动部署

#### 步骤 1: 准备环境

```bash
# 创建必要的目录
mkdir -p config/secrets config/certs config/agents/main/agent docker/input

# 设置目录权限
chmod 700 config/secrets
chmod 700 config/certs
```

#### 步骤 2: 配置 Gateway Token

```bash
# 生成 Gateway Token
openssl rand -hex 32 > config/secrets/gateway_token
chmod 600 config/secrets/gateway_token

# 验证 Token
cat config/secrets/gateway_token
```

#### 步骤 3: 配置 SSL 证书

**选项 A: 使用自签名证书（测试环境）**
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout config/certs/server.key \
    -out config/certs/server.crt \
    -subj "/C=CN/ST=State/L=City/O=OpenClaw/CN=localhost"

chmod 600 config/certs/server.key
chmod 644 config/certs/server.crt
```

**选项 B: 使用受信任证书（生产环境）**
```bash
# 将您的证书和私钥复制到 config/certs/
cp your_certificate.crt config/certs/server.crt
cp your_private.key config/certs/server.key

chmod 600 config/certs/server.key
```

#### 步骤 4: 配置 AI 模型

编辑 `config/agents/main/agent/models.json`：

```json
{
  "providers": {
    "deepseek": {
      "baseUrl": "https://api.deepseek.com/v1",
      "apiKey": "${DEEPSEEK_API_KEY}",
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
```

**安全提示**: 使用 `${DEEPSEEK_API_KEY}` 环境变量引用，而非硬编码 API Key。

#### 步骤 5: 启动服务

```bash
cd docker

# 构建并启动
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# 查看日志
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f
```

## 安全配置详解

### Docker Secrets

Gateway Token 通过 Docker Secrets 安全注入：

```yaml
secrets:
  gateway_token:
    file: ../config/secrets/gateway_token
```

优势：
- Token 不暴露在环境变量中
- 文件权限严格控制（600）
- 支持 Docker Swarm 加密存储

### 卷挂载策略

| 路径 | 挂载方式 | 说明 |
|------|----------|------|
| `/home/node/.openclaw` | 命名卷 | 持久化数据，可写 |
| `/home/node/.openclaw/agents/main/agent` | 命名卷 | 运行时配置，可写 |
| `/tmp/openclaw_config/openclaw.json` | 只读绑定挂载 | 启动时复制到可写卷 |
| `/tmp/openclaw_config/certs` | 只读绑定挂载 | SSL 证书 |
| `/home/node/openclaw_input` | 只读绑定挂载 | 输入文件 |

### 安全选项

```yaml
read_only: true          # 只读根文件系统
cap_drop: ALL            # 丢弃所有 Linux 能力
user: node               # 非 root 用户运行
```

## 安全监控

### 实时监控

```bash
# 启动安全监控
./scripts/security_monitor.sh monitor
```

功能：
- 实时日志分析
- 异常自动检测
- 安全事件告警
- 彩色高亮显示

### 定期检查

```bash
# 执行安全检查
./scripts/security_monitor.sh check
```

检查项：
- 容器运行状态
- 文件权限安全
- API Key 配置
- 网络连接状态
- 日志异常检测

### 生成报告

```bash
# 生成安全报告
./scripts/security_monitor.sh report
```

报告包含：
- 容器状态
- 镜像信息
- 卷挂载情况
- 告警历史
- 文件权限
- 网络连接

## 故障排除

### 问题 1: EROFS 错误仍然存在

**症状**: 日志中仍然出现 `EROFS: read-only file system`

**解决**:
```bash
# 1. 停止服务
cd docker
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# 2. 清理卷（注意：会丢失数据）
docker volume rm openclaw-data openclaw-agent-config

# 3. 重新部署
./scripts/deploy_production.sh
```

### 问题 2: WebSocket 连接失败 (1008)

**症状**: 浏览器显示 `device token mismatch`

**解决**:
```bash
# 修复 Token 不匹配
./scripts/fix_token_mismatch.sh --fix
```

### 问题 3: API Key 无效

**症状**: 模型调用失败，日志显示认证错误

**解决**:
1. 检查 `config/agents/main/agent/models.json` 中的 API Key
2. 确认使用环境变量格式：`${API_KEY_NAME}`
3. 在 `docker/.env` 文件中配置实际的 API Key

### 问题 4: 证书错误

**症状**: 浏览器显示证书不受信任

**解决**:
- 测试环境：接受自签名证书例外
- 生产环境：配置受信任的 SSL 证书

## 最佳实践

### 1. 定期维护

```bash
# 每周执行
./scripts/security_monitor.sh check

# 每月执行
./scripts/rotate_token.sh  # 轮换 Gateway Token
docker system prune -f       # 清理无用镜像
```

### 2. 备份策略

```bash
# 备份配置
tar -czf backup_$(date +%Y%m%d).tar.gz config/

# 备份卷数据
docker run --rm -v openclaw-data:/data -v $(pwd):/backup alpine tar czf /backup/data_backup.tar.gz -C /data .
```

### 3. 更新升级

```bash
# 1. 备份当前配置
cp -r config/ config.backup.$(date +%Y%m%d)

# 2. 拉取最新镜像
cd docker
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull

# 3. 重新构建
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# 4. 验证服务
./scripts/security_monitor.sh check
```

### 4. 防火墙配置

```bash
# 仅允许必要的端口
sudo ufw allow 18789/tcp  # OpenClaw Gateway
sudo ufw allow 22/tcp     # SSH
sudo ufw enable

# 或者使用 iptables
sudo iptables -A INPUT -p tcp --dport 18789 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -P INPUT DROP
```

## 安全加固清单

- [ ] Gateway Token 使用 Docker Secrets 管理
- [ ] SSL/TLS 证书配置（生产环境使用受信任证书）
- [ ] API Keys 使用环境变量，不硬编码
- [ ] 文件权限正确设置（secrets 600, certs 600/644）
- [ ] 启用只读根文件系统
- [ ] 丢弃不必要的 Linux 能力
- [ ] 配置防火墙规则
- [ ] 启用日志审计
- [ ] 定期轮换敏感凭证
- [ ] 配置监控告警

## 参考文档

- [Docker Secrets 文档](https://docs.docker.com/engine/swarm/secrets/)
- [Docker 安全最佳实践](https://docs.docker.com/develop/dev-best-practices/)
- [OpenClaw 多提供商配置](MULTI_PROVIDER_SETUP.md)
- [OpenClaw 安全审计报告](SECURITY_AUDIT_REPORT_V2.md)

## 获取帮助

遇到问题？请按以下步骤获取帮助：

1. 查看日志：`docker compose logs -f`
2. 执行检查：`./scripts/security_monitor.sh check`
3. 查看文档：`docs/`
4. 提交 Issue：提供日志和配置信息
