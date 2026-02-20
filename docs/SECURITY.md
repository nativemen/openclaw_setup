# OpenClaw 安全与隐私保护指南

本文档说明 OpenClaw 部署中的网络安全和隐私保护措施。

---

## 安全架构概述

```
┌─────────────────────────────────────────────────────────────┐
│                        用户设备                             │
│  ┌─────────────────┐    ┌─────────────────────────────┐   │
│  │   本地 Ollama   │    │     OpenClaw Gateway       │   │
│  │  (完全离线)     │    │     (Docker 容器)          │   │
│  └────────┬────────┘    └──────────────┬──────────────┘   │
│           │                             │                   │
│           │                    ┌────────┴────────┐        │
│           │                    │  本地网络        │        │
│           │                    └────────┬────────┘        │
└──────────┼─────────────────────────────┼──────────────────┘
           │                             │
           │         ┌───────────────────┘
           │         │
           ▼         ▼
    ┌──────────────────────────────────────┐
    │         外部 API (可选)                │
    │  - DeepSeek                          │
    │  - Google (Gemini)                    │
    │  - Anthropic (Claude)                 │
    └──────────────────────────────────────┘
```

---

## 核心安全原则

### 1. 数据本地化处理

| 数据类型 | 处理方式 | 风险等级 |
|---------|---------|---------|
| 简历内容 | 100% 本地处理 | 低 |
| 个人信息 | 存储在本地 | 低 |
| API 密钥 | 加密存储 | 中 |
| 通信日志 | 可配置存储位置 | 低 |

### 2. API 密钥保护

#### 存储策略
- API 密钥存储在 `~/.openclaw/secrets/` 目录
- 不提交到 Git 仓库
- 使用系统密钥链 (Keychain/Windows Credential Manager)

#### 环境变量方式
```bash
# 在 config/env/*.env 中配置
ANTHROPIC_API_KEY=sk-ant-...  # 不包含在版本控制中
```

#### 密钥文件方式
```bash
# 创建密钥文件
echo "sk-ant-..." > ~/.openclaw/secrets/anthropic.key
chmod 600 ~/.openclaw/secrets/anthropic.key
```

### 3. 网络隔离

#### 本地优先策略
- 优先使用 Ollama 本地模型
- 所有简历数据在本地处理
- 不上传到任何云服务

#### 代理配置
```bash
# config/env/proxy.env
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,ollama
```

---

## Docker 安全配置

### 1. 容器隔离

```yaml
# docker/docker-compose.yml
services:
  openclaw-gateway:
    # 只绑定到本地回环接口
    ports:
      - "127.0.0.1:18789:18789"

    # 使用非 root 用户
    user: "node:node"

    # 只读根文件系统
    read_only: true

    # 使用 tmpfs 存储临时文件
    tmpfs:
      - /tmp:size=100m,mode=1777

    # 丢弃所有 Linux 能力
    cap_drop:
      - ALL

    # 限制资源
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2.0'

    # 安全选项
    security_opt:
      - no-new-privileges:true
```

### 2. 网络隔离

```yaml
networks:
  openclaw-network:
    driver: bridge
    # 仅暴露必要端口
```

### 3. 数据卷隔离

```yaml
volumes:
  # 只读挂载输入目录
  - ./input:/home/node/openclaw_input:ro

  # 只读挂载工作空间
  - ./workspace:/home/node/.openclaw/workspace:ro
```

---

## 隐私保护措施

### 1. 数据处理流程

```
输入文档 (PDF/Word/Markdown)
        │
        ▼
┌───────────────────┐
│   本地处理        │  ← 不离开本地网络
│  (OpenClaw)      │
└───────────────────┘
        │
        ▼
生成简历 (Markdown)
        │
        ▼
┌───────────────────┐
│   本地存储        │
│  (~/.openclaw/)  │
└───────────────────┘
```

### 2. 敏感信息保护

- **不在日志中记录**: API 密钥、个人信息
- **临时文件清理**: 处理完成后自动删除
- **内存保护**: 敏感数据使用后立即清除

### 3. 审计日志

```json
// config/openclaw.json
{
  "logging": {
    "level": "info",
    "file": "~/.openclaw/logs/openclaw.log",
    "excludePaths": ["/api/keys", "/api/secrets", "/api/auth"],
    "sanitize": true
  }
}
```

---

## 推荐的安全配置

### 1. 最小权限原则

```yaml
# docker-compose.yml
services:
  openclaw-gateway:
    read_only: true          # 容器只读
    tmpfs:
      - /tmp                 # 使用 tmpfs 存储临时文件
    cap_drop:
      - ALL                  # 丢弃所有能力
    volumes:
      - ./workspace:/data   # 仅挂载必要目录 (只读)
```

### 2. 防火墙规则

```bash
# 允许的出站连接 (可选)
# 只允许访问必要的 API 端点
iptables -A OUTPUT -d api.anthropic.com -j ACCEPT
iptables -A OUTPUT -d api.deepseek.com -j ACCEPT
iptables -A OUTPUT -j DROP
```

### 3. 密钥轮换

定期更换 API 密钥：
- 每 90 天更换一次
- 使用不同的密钥用于不同服务
- 监控使用情况

---

## Token 安全配置

### 1. Token 管理原则

| 安全措施 | 说明 | 状态 |
|---------|------|------|
| 环境变量存储 | Token 存储在环境变量而非代码 | ✅ 已实施 |
| 动态生成 | 启动时自动生成随机 Token | ✅ 已实施 |
| Token 轮换 | 支持定期更换 Token | ✅ 已实施 |
| Header 认证 | 使用 Authorization Header 而非 URL 参数 | ✅ 已实施 |
| IP 白名单 | 限制可访问的 IP 地址 | ✅ 已实施 |

### 2. Token 配置方式

#### 环境变量方式 (推荐)
```bash
# config/env/.env
OPENCLAW_GATEWAY_TOKEN=your-secure-random-token-here
```

#### Token 轮换
```bash
# 查看当前 Token
./scripts/rotate_token.sh --show

# 轮换 Token
./scripts/rotate_token.sh --rotate

# 验证 Token
./scripts/rotate_token.sh --validate
```

### 3. 认证方式

#### 正确的认证方式 (推荐)
```bash
# 使用 Authorization Header
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:18789/

# 或使用 Authorization 头
curl -H "Authorization: YOUR_TOKEN" http://localhost:18789/
```

#### 不推荐的方式
```bash
# ❌ 禁止: URL 参数传递 Token (会被记录在日志中)
curl "http://localhost:18789/?token=YOUR_TOKEN"
```

### 4. IP 白名单配置

```json
// config/openclaw.json
{
  "security": {
    "ipWhitelist": {
      "enabled": true,
      "allowedIPs": ["127.0.0.1", "::1", "localhost"]
    }
  }
}
```

### 5. 生产环境 HTTPS 配置

```json
// config/openclaw.json
{
  "security": {
    "https": {
      "enabled": true,
      "certPath": "/path/to/certificate.crt",
      "keyPath": "/path/to/private.key"
    }
  }
}
```

#### 生成自签名证书 (测试用)
```bash
# 生成私钥
openssl genrsa -out server.key 2048

# 生成证书
openssl req -new -x509 -key server.key -out server.crt -days 365
```

---

## 生产环境安全建议

### 1. 密钥管理服务

推荐使用专业密钥管理服务：

| 服务 | 特点 | 适用场景 |
|------|------|---------|
| HashiCorp Vault | 企业级、功能全面 | 大规模部署 |
| AWS Secrets Manager | AWS 集成 | AWS 云环境 |
| Azure Key Vault | Azure 集成 | Azure 云环境 |
| Doppler | 开发者友好 | 中小项目 |

### 2. Docker Secrets (Swarm 模式)

```yaml
# docker-compose.yml
services:
  openclaw-gateway:
    secrets:
      - gateway_token
    environment:
      - OPENCLAW_GATEWAY_TOKEN_FILE=/run/secrets/gateway_token

secrets:
  gateway_token:
    file: ./secrets/gateway_token.txt
```

### 3. Kubernetes Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-secrets
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: your-secure-token
  AI_API_KEY: your-api-key
```

### 4. 网络隔离建议

```bash
# 使用网络策略限制访问
# Kubernetes NetworkPolicy 示例
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-network-policy
spec:
  podSelector:
    matchLabels:
      app: openclaw-gateway
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
```

---

## 安全加固功能

### 本次更新新增的安全特性

1. **只读容器**: `read_only: true` 防止容器内文件被修改
2. **临时文件系统**: tmpfs 用于 /tmp，防止敏感数据写入磁盘
3. **能力丢弃**: `cap_drop: ALL` 最小化容器权限
4. **本地绑定**: 只绑定到 127.0.0.1，防止外部访问
5. **只读卷挂载**: workspace 和 input 目录只读挂载
6. **Shell 脚本安全**: 使用 `set -euo pipefail` 严格模式
7. **动态 Token**: 启动时自动生成随机 Token
8. **Header 认证**: 使用 Authorization Header 而非 URL 参数
9. **Token 轮换**: 支持定期更换 Token
10. **IP 白名单**: 限制可访问的 IP 地址

---

## 风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| API 密钥泄露 | 低 | 高 | 加密存储、环境变量 |
| 数据外泄 | 低 | 高 | 本地处理、网络隔离 |
| 容器逃逸 | 极低 | 高 | 限制权限、安全选项 |
| 中间人攻击 | 低 | 中 | HTTPS、证书验证 |
| 外部未授权访问 | 低 | 高 | 本地绑定、Token认证 |
| 资源耗尽 | 中 | 中 | 资源限制、配额控制 |

---

## 应急响应

### 发现安全事件时

1. **立即隔离**
   ```bash
   ./scripts/stop_gateway.sh
   # 或
   docker compose down
   ```

2. **检查日志**
   ```bash
   docker compose logs > incident_log.txt
   ```

3. **更换密钥**
   - 登录各服务后台更换 API Key
   - 更新本地配置文件

4. **重新部署**
   - 确保安全补丁已应用
   - 使用新的 API Key

---

## 合规建议

### 中国网络安全法

- 数据本地化存储: ✓ (默认)
- 用户协议: 建议添加
- 数据保留: 定期清理

### GDPR (如适用)

- 数据访问权: 用户可导出所有数据
- 数据删除权: 支持完全删除
- 数据转移: 支持导出为标准格式

---

## 验证清单

部署完成后，请验证以下安全设置：

- [ ] API 密钥未提交到 Git
- [ ] 配置文件已添加到 .gitignore
- [ ] Docker 容器使用非 root 用户
- [ ] 端口 18789 仅本地访问 (127.0.0.1)
- [ ] 容器为只读模式 (read_only: true)
- [ ] tmpfs 已配置用于临时文件
- [ ] cap_drop: ALL 已设置
- [ ] 代理配置正确 (如使用代理)
- [ ] 日志中无敏感信息
- [ ] 本地模型可正常工作

---

## 更多信息

- [OpenClaw 官方安全文档](https://docs.openclaw.ai/gateway/security)
- [Docker 安全最佳实践](https://docs.docker.com/engine/security/)
- [OWASP 安全指南](https://owasp.org/)
