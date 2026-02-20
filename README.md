# OpenClaw 一键部署方案

## 项目概述

本项目提供 OpenClaw 的一键部署解决方案，支持多种 LLM 提供商的接入：
- **DeepSeek** (在线 API)
- **Gemini** (Google)
- **Claude** (Anthropic)
- **Ollama** (本地模型)

### 核心用途
- 本地英文简历自动生成
- 面向嵌入式软件工程师的求职文档
- 支持双语输出（中英文）和纯英文版本

---

## 目录结构

```
openclaw_setup/
├── README.md                          # 项目说明
├── LICENSE                            # 许可证
├── .gitignore                         # Git 忽略配置
│
├── scripts/                           # 部署脚本目录
│   ├── build.sh                      # 构建和部署主脚本
│   ├── start_gateway.sh              # 启动 Gateway (主要入口)
│   ├── stop_gateway.sh               # 停止 Gateway
│   ├── init_build_dirs.sh            # 初始化 build 目录
│   ├── generate_openclaw_config.sh   # 生成动态配置文件
│   ├── setup_agent_auth.sh            # 嵌入式代理认证配置
│   ├── setup_ollama.sh               # Ollama 本地模型设置
│   ├── health_check.sh               # 健康检查脚本
│   ├── deploy_production.sh          # 生产环境部署
│   ├── start_with_token.sh           # Docker Secrets 模式启动
│   ├── configure_https.sh            # HTTPS 配置
│   ├── fix_token_mismatch.sh         # Token 问题修复
│   ├── rotate_token.sh               # Token 轮换
│   ├── security_check.sh             # 安全检查
│   ├── security_monitor.sh           # 安全监控
│   ├── migrate_token.sh              # Token 迁移
│   └── fix_token_mismatch.sh         # Token 不匹配修复
│
├── config/                            # 配置文件目录
│   ├── openclaw.json                 # OpenClaw 主配置
│   │
│   └── providers/                    # LLM 提供商配置
│       ├── claude.yaml              # Claude 模型配置
│       ├── gemini.yaml              # Gemini 模型配置
│       ├── deepseek.yaml            # DeepSeek 模型配置
│       └── ollama.yaml              # Ollama 本地模型配置
│
├── docker/                           # Docker 配置
│   ├── Dockerfile                    # Docker 镜像构建
│   ├── docker-compose.yml           # Docker Compose 配置 (开发环境)
│   └── docker-compose.prod.yml       # Docker Compose 配置 (生产环境)
│
└── docs/                            # 文档目录
    ├── SETUP_GUIDE.md               # 设置指南
    ├── MULTI_PROVIDER_SETUP.md      # 多提供商设置指南
    ├── PRODUCTION_DEPLOYMENT.md    # 生产部署指南
    └── SECURITY.md                  # 安全和隐私保护说明
```

---

## 功能特性

### 1. 一键部署
- 自动检测并安装依赖（Node.js、Docker、Ollama）
- 支持 WSL2 环境下的 Windows 部署
- 自动化配置验证
- 开发/生产模式一键切换

### 2. 多 LLM 提供商支持
| 提供商 | 模型 | 用途 | 配置方式 |
|--------|------|------|----------|
| DeepSeek | deepseek-chat | 免费无限额，推荐 | API Key |
| DeepSeek | deepseek-coder | 编程任务 | API Key |
| DeepSeek | deepseek-reasoner (R1) | 推理任务 | API Key |
| Google Gemini | gemini-2.0-flash | 快速响应 | API Key |
| Google Gemini | gemini-2.0-pro | 高质量任务 | API Key |
| Anthropic Claude | claude-opus-4-5 | 最高质量 | API Key |
| Anthropic Claude | claude-sonnet-4-5 | 平衡性能 | API Key |
| Ollama | llama3.1:8b | 本地离线模型 | 本地运行 |
| Ollama | llama3.1:70b | 高质量本地模型 | 本地运行 |

### 3. 网络安全与隐私保护
- API 密钥加密存储
- 支持 HTTP/SOCKS 代理
- 本地模型数据不外传
- 敏感信息与配置文件分离
- Docker Secrets 安全注入
- Token 轮换支持
- 实时安全监控

### 4. 简历生成功能
- 支持输入本地文档（PDF、Word、Markdown）
- 输出格式：Markdown、PDF、DOCX
- 双语版本（中英文）和纯英文版本

### 5. 安全特性
- 只读根文件系统
- 非 root 用户运行
- 临时文件系统 (tmpfs)
- Linux 能力限制
- IP 白名单支持
- HTTPS 支持
- 授权 Header 认证

---

## 快速开始

### 前置要求
- Windows 10/11 with WSL2 / Linux / macOS
- Docker Desktop 或 Docker Engine
- 4GB+ RAM (使用本地模型需要 8GB+)
- 20GB+ 可用磁盘空间

### 部署步骤

```bash
# 1. 克隆或进入项目目录
cd openclaw_setup

# 2. 运行构建部署脚本
./scripts/build.sh

# 3. 启动 OpenClaw Gateway (会提示选择 AI 大模型)
./scripts/start_gateway.sh
# 选择: 1) DeepSeek  2) Gemini  3) Claude  4) Ollama

# 4. 访问 Web UI
# http://localhost:18789
```

---

## 配置详解

### 统一环境配置

运行 `./scripts/start_gateway.sh` 时，会通过交互式菜单选择要使用的 AI 大模型。

配置文件: `build/runtime/env/.env`

```bash
# Gateway Token (自动生成)
OPENCLAW_GATEWAY_TOKEN=your-auto-generated-token

# AI 提供商选择 (claude/deepseek/gemini/ollama)
AI_PROVIDER=deepseek

# 模型名称 (会根据 AI_PROVIDER 自动设置默认值)
AI_MODEL=deepseek-chat

# API 基础 URL (会根据 AI_PROVIDER 自动设置)
AI_API_BASE_URL=https://api.deepseek.com

# 多提供商 API Keys (全部配置，支持运行时切换)
DEEPSEEK_API_KEY=your-deepseek-key-here
ANTHROPIC_API_KEY=your-anthropic-key-here
GEMINI_API_KEY=your-gemini-key-here

# 代理设置 (可选)
AI_PROXY=

# 请求超时 (毫秒)
AI_TIMEOUT=120000

# 最大重试次数
AI_MAX_RETRIES=3
```

### 代理配置 (可选)
```bash
# 在 build/runtime/env/proxy.env 中配置
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,ollama
```

---

## 安全特性

### 1. 密钥管理
- API 密钥存储在 `build/runtime/secrets/`
- 使用 Docker Secrets 安全注入
- 配置文件 `.gitignore` 自动忽略敏感文件

### 2. 网络隔离
- 本地 Ollama 模型完全离线运行
- 仅在用户明确授权时发送数据到外部 API
- 支持本地网络优先策略

### 3. 隐私保护
- 简历数据仅在本地处理
- 不上传到任何第三方服务
- 可选: 使用防火墙限制出站连接

### 4. 容器安全
- 只读根文件系统
- 非 root 用户运行 (node:node)
- 临时文件系统 (tmpfs)
- 丢弃所有 Linux 能力 (cap_drop: ALL)
- 资源限制 (内存、CPU)

---

## 部署模式

### 开发模式
```bash
# 使用环境变量配置
./scripts/start_gateway.sh
# 选择 "开发/测试模式"
```

特点：
- 配置简单，快速启动
- 使用环境变量传递配置
- 允许未配置模式运行

### 生产模式
```bash
# 使用 Docker Secrets
./scripts/start_gateway.sh
# 选择 "生产模式"
```

特点：
- 更安全：使用 Docker Secrets 存储敏感信息
- 只读根文件系统
- 最小化权限
- 完整安全加固

---

## 故障排除

### 常见问题

**Q: Docker 启动失败**
A: 根据您的环境选择解决方法：
- **Docker Desktop**: 确保 Docker Desktop 已启动
- **WSL2 原生 Docker**: 运行 `sudo service docker start`

**Q: API 密钥验证失败**
A: 检查密钥是否正确配置，检查是否有特殊字符

**Q: 无法访问 Web UI**
A: 检查端口 18789 是否被占用: `netstat -an | grep 18789`

**Q: WebSocket 认证失败 (错误 1008)**
A: 运行 Token 修复脚本:
```bash
./scripts/fix_token_mismatch.sh --fix
```

**Q: Ollama 模型下载慢**
A: 可以配置国内镜像源，或使用 VPN/代理下载模型

### 安全检查
```bash
# 执行安全检查
./scripts/security_check.sh

# 启动安全监控
./scripts/security_monitor.sh monitor

# 定期检查
./scripts/security_monitor.sh check
```

---

## Token 管理

### Token 轮换
```bash
# 查看当前 Token
./scripts/rotate_token.sh --show

# 轮换 Token
./scripts/rotate_token.sh --rotate

# 验证 Token
./scripts/rotate_token.sh --validate
```

### Token 修复
```bash
# 修复 Token 不匹配
./scripts/fix_token_mismatch.sh --fix

# 检查 Token 状态
./scripts/fix_token_mismatch.sh --check
```

---

## 参考文档

- [设置指南](docs/SETUP_GUIDE.md)
- [多提供商设置](docs/MULTI_PROVIDER_SETUP.md)
- [生产部署](docs/PRODUCTION_DEPLOYMENT.md)
- [安全说明](docs/SECURITY.md)

---

## 许可证

MIT License - 详见 LICENSE 文件

---

## 参考链接

- [OpenClaw 官方文档](https://docs.openclaw.ai)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [DeepSeek](https://www.deepseek.com/)
- [Google Gemini](https://gemini.google.com/)
- [Anthropic Claude](https://www.anthropic.com/)
- [Ollama](https://ollama.com/)
