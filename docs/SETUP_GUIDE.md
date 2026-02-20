# OpenClaw 部署设置指南

本指南将帮助您完成 OpenClaw 的一键部署，支持 DeepSeek、Gemini、Claude 和 Ollama (本地 Llama) 模型。

## 前置要求

### 硬件要求
- **操作系统**: Windows 10/11 (WSL2), Linux, macOS
- **内存**: 4GB+ RAM (使用本地模型需要 8GB+)
- **存储空间**: 20GB+ 可用磁盘空间
- **网络**: 可访问 OpenAI/Anthropic/Google API (或配置代理)

### 软件要求
- Docker (Docker Desktop 或 Docker Engine)
- Node.js 22+ (通过 Docker 运行则不需要)
- Git

---

## 安装 Docker

### 方案 1: Windows + WSL2 + Docker Desktop (推荐)

如果您在 Windows 上使用 WSL2：

1. 下载并安装 [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)
2. 启动 Docker Desktop
3. 进入 Settings → General，勾选 "Use the WSL 2 based engine"
4. 进入 Settings → Resources → WSL Integration，启用您的 WSL 发行版
5. 在 WSL2 终端中运行 `docker ps` 验证安装

### 方案 2: WSL2/Linux 原生 Docker

如果您想在 WSL2 或 Linux 中直接运行 Docker（无需 Docker Desktop）：

```bash
# 安装 Docker Engine
sudo apt-get update
sudo apt-get install -y docker.io

# 启动 Docker 服务
sudo service docker start

# 将当前用户添加到 docker 组
sudo usermod -aG docker $USER

# 重新登录 WSL 使配置生效
# 然后验证安装
docker ps
```

### 方案 3: macOS

```bash
# 使用 Homebrew
brew install --cask docker
# 或下载 Docker Desktop for Mac
```

---

## 快速开始

### 步骤 1: 克隆项目

```bash
git clone https://github.com/your-repo/openclaw_setup.git
cd openclaw_setup
```

### 步骤 2: 运行构建部署脚本

```bash
chmod +x scripts/build.sh
./scripts/build.sh
```

### 步骤 3: 启动 Gateway 并选择 AI 大模型

```bash
./scripts/start_gateway.sh
```

运行启动脚本时，会显示交互式菜单让您选择 AI 大模型：

```
请选择要使用的 AI 提供商:
  1) DeepSeek  (性价比高，推荐)
  2) Gemini    (Google)
  3) Claude     (Anthropic)
  4) Ollama    (本地模型，离线可用)
```

选择后脚本会自动配置对应的 API 地址和默认模型。

### 步骤 4: 访问 Web UI

打开浏览器访问: http://localhost:18789

---

## 构建脚本命令

`build.sh` 支持以下命令：

```bash
# 完整部署（默认）
./scripts/build.sh

# 启动 Gateway
./scripts/build.sh start

# 清理运行时数据，保留核心配置（API Keys, 环境变量等）
./scripts/build.sh clean

# 完全清理，删除所有构建产物（会提示确认）
./scripts/build.sh distclean

# 显示帮助信息
./scripts/build.sh --help
```

---

## 配置详解

### 统一环境配置

所有 AI 大模型的配置统一保存在 `config/env/.env` 文件中：

```bash
# AI 提供商选择 (claude/deepseek/gemini/ollama)
AI_PROVIDER=claude

# API Key (根据选择的 AI_PROVIDER 填写对应的 API Key)
AI_API_KEY=your-api-key-here

# 模型名称
AI_MODEL=claude-sonnet-4-20250514

# API 基础 URL
AI_API_BASE_URL=https://api.anthropic.com

# 代理设置 (可选)
AI_PROXY=

# 请求超时 (毫秒)
AI_TIMEOUT=120000

# 最大重试次数
AI_MAX_RETRIES=3
```

### 各提供商 API Key 获取

| 提供商 | 获取地址 |
|--------|----------|
| DeepSeek | https://platform.deepseek.com/ |
| Gemini | https://aistudio.google.com/app/apikey |
| Claude | https://console.anthropic.com/ |
| Ollama | 本地模型，无需 API Key |

### Ollama 本地模型 (可选)

如需使用本地模型：

```bash
# 运行 Ollama 安装脚本
./scripts/setup_ollama.sh

# 选择下载模型 (推荐 llama3.1:8b)
```

---

## 配置代理 (可选)

如果您在中国大陆或需要通过代理访问 API：

1. 编辑 `config/env/proxy.env`:
   ```bash
   HTTP_PROXY=http://127.0.0.1:7890
   HTTPS_PROXY=http://127.0.0.1:7890
   ```

2. 在使用 Docker 时，代理设置会自动传递到容器内。

---

## 使用 Docker 部署

### 构建镜像

```bash
cd docker
docker build -t openclaw-local .
```

### 运行容器

```bash
docker-compose up -d
```

### 查看日志

```bash
docker-compose logs -f
```

---

## 验证部署

运行健康检查脚本：

```bash
./scripts/health_check.sh
```

预期输出：
- Gateway 服务: ✓ 正常
- Docker 容器: ✓ 运行中
- API 密钥: ✓ 已配置

---

## 常见问题

### Q: Docker 启动失败
A: 根据您的环境选择解决方法：
- **Docker Desktop**: 确保 Docker Desktop 已启动
- **WSL2 原生 Docker**: 运行 `sudo service docker start`
- **检查错误**: 运行 `docker ps` 查看具体错误信息

### Q: Docker 权限不足
A: 如果遇到 "permission denied" 错误：
```bash
sudo usermod -aG docker $USER
# 重新登录使配置生效
```

### Q: API 密钥验证失败
A: 检查密钥是否正确复制，是否包含多余空格或特殊字符。

### Q: 无法访问 Web UI
A: 检查端口 18789 是否被占用: `netstat -an | grep 18789`

### Q: Ollama 模型下载慢
A: 可以配置国内镜像源，或使用 VPN/代理下载模型。

---

## 下一步

- 查看 [LLM 提供商设置指南](PROVIDERS_SETUP.md)
- 查看 [简历生成使用指南](RESUME_GENERATION.md)
- 查看 [安全与隐私保护说明](SECURITY.md)
