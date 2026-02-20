# OpenClaw 多提供商配置指南

本文档说明如何配置和使用 OpenClaw 的多提供商支持，允许在运行时动态切换 AI 提供商。

## 概述

OpenClaw 原生支持运行时切换 Provider，无需重建容器。通过配置多个提供商的 API Keys，您可以在聊天中随时切换模型。

## 支持的提供商

- **DeepSeek** (`deepseek`) - 默认提供商，性价比高
- **Google Gemini** (`google`) - 长上下文支持
- **Anthropic Claude** (`anthropic`) - 强大的推理能力
- **OpenAI** (`openai`) - GPT 系列模型

## 配置文件结构

### 1. 环境变量文件 (`docker/.env`)

```bash
# Gateway Token
OPENCLAW_GATEWAY_TOKEN=your-token-here

# 默认 AI 提供商配置
AI_PROVIDER=deepseek
AI_MODEL=deepseek/deepseek-chat
AI_API_BASE_URL=https://api.deepseek.com

# 多提供商 API Keys（支持运行时切换）
DEEPSEEK_API_KEY=sk-deepseek-xxx
ANTHROPIC_API_KEY=sk-ant-xxx
GEMINI_API_KEY=gemini-xxx
OPENAI_API_KEY=sk-openai-xxx
```

### 2. OpenClaw 配置 (`config/openclaw.json`)

配置文件已更新为包含所有提供商：

```json
{
  "models": {
    "providers": {
      "deepseek": {
        "apiKey": "${DEEPSEEK_API_KEY}",
        "models": ["deepseek-chat", "deepseek-coder", "deepseek-reasoner"]
      },
      "anthropic": {
        "apiKey": "${ANTHROPIC_API_KEY}",
        "models": ["claude-opus-4-6", "claude-sonnet-4-5"]
      },
      "google": {
        "apiKey": "${GEMINI_API_KEY}",
        "models": ["gemini-2.0-flash", "gemini-2.0-pro"]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "deepseek/deepseek-chat",
        "fallbacks": [
          "deepseek/deepseek-coder",
          "anthropic/claude-sonnet-4-5",
          "google/gemini-2.0-flash"
        ]
      }
    }
  }
}
```

## 使用方法

### 启动 Gateway

```bash
./scripts/start_gateway.sh
```

脚本会引导您配置所有提供商的 API Keys。

### 运行时切换 Provider

#### 方法 1: 聊天命令（推荐）
在 WebChat 或任何频道中发送：
```
/model list                    # 列出所有可用模型
/model 2                       # 选择第2个模型
/model anthropic/claude-sonnet-4-5   # 切换到 Claude
/model deepseek/deepseek-chat         # 切换回 DeepSeek
/model google/gemini-2.0-flash        # 切换到 Gemini
```

#### 方法 2: CLI 命令
```bash
openclaw models set anthropic/claude-opus-4-6
openclaw models set deepseek/deepseek-chat
openclaw models set google/gemini-2.0-flash
```

#### 方法 3: 自动故障转移
当主模型失败时，自动切换到备用模型（已在配置中设置）。

## 健康检查

检查所有提供商配置状态：
```bash
./scripts/health_check.sh
```

输出示例：
```
检查配置...
  ✓ 配置文件存在: docker/.env

  多提供商 API Keys 配置:
    ✓ DeepSeek API Key 已配置
    ✓ Gemini API Key 已配置
    ✓ Anthropic (Claude) API Key 已配置
    ! OpenAI API Key 未配置

  ✓ 共 3 个提供商已配置 (支持运行时切换)
  ✓ 当前默认 AI Provider: deepseek
  ✓ 默认模型: deepseek/deepseek-chat
```

## 添加新的提供商

1. 在 `docker/.env` 中添加 API Key：
```bash
NEW_PROVIDER_API_KEY=sk-xxx
```

2. 在 `docker/docker-compose.yml` 中添加环境变量：
```yaml
environment:
  - NEW_PROVIDER_API_KEY=${NEW_PROVIDER_API_KEY:-}
```

3. 在 `config/openclaw.json` 中添加提供商配置：
```json
{
  "models": {
    "providers": {
      "new-provider": {
        "baseUrl": "https://api.new-provider.com/v1",
        "apiKey": "${NEW_PROVIDER_API_KEY}",
        "api": "openai-completions",
        "models": [{"id": "model-id", "name": "Model Name"}]
      }
    }
  }
}
```

4. 更新 `scripts/start_gateway.sh` 中的提供商映射（可选，用于交互式配置）。

## 故障排除

### 模型切换失败
- 检查目标提供商的 API Key 是否已配置
- 查看 Gateway 日志：`docker logs openclaw-gateway`

### API Key 未生效
- 确保在 `docker/.env` 和 `docker-compose.yml` 中都添加了环境变量
- 重启容器：`docker compose restart`

### 提供商未显示在列表中
- 检查 `config/openclaw.json` 中的 `models.providers` 配置
- 验证环境变量是否正确传递：`docker exec openclaw-gateway env | grep API_KEY`

## 最佳实践

1. **至少配置 2 个提供商** - 确保在一个服务中断时有备用选项
2. **使用 DeepSeek 作为默认** - 性价比高，适合日常使用
3. **Gemini 用于长文本** - 利用其超大上下文窗口
4. **Claude 用于复杂推理** - 在需要深度思考时切换

## 参考文档

- [OpenClaw 官方模型文档](https://docs.openclaw.ai/concepts/models)
- [模型故障转移](https://docs.openclaw.ai/concepts/model-failover)
- [提供商配置](https://docs.openclaw.ai/concepts/model-providers)
