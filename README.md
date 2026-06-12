# AI 视觉对话助手

AI 通过摄像头看到你，通过麦克风听到你，实时语音对话。

## 技术栈

| 层 | 技术 | 说明 |
|---|------|------|
| **运行时** | Node.js 18+ | JavaScript 全栈 |
| **HTTP 框架** | Express 4.x | 静态文件服务 + API |
| **WebSocket** | ws 8.x | 浏览器 ↔ 服务端双向通信 |
| **AI SDK** | openai 4.x | 阶跃星辰 API（OpenAI 兼容协议） |
| **实时语音** | stepfun-realtime-api 0.1 | 阶跃星辰 Realtime WebSocket（VAD + ASR + LLM + TTS） |
| **图片处理** | sharp 0.33 | 摄像头帧压缩 |
| **环境变量** | dotenv 16.x | .env 配置管理 |
| **前端** | 原生 HTML/CSS/JS | 无框架，浏览器 Web API |

## 阶跃星辰模型

| 功能 | 模型 | 接口 |
|------|------|------|
| 视觉理解 | `step-3.7-flash` | `POST /v1/chat/completions`（多模态 image） |
| 实时语音 | `step-1o-audio` | `wss://api.stepfun.com/v1/realtime` |
| 文字对话 | `step-3.7-flash` | `POST /v1/chat/completions` |

## 架构

```
┌─ 浏览器 (localhost:8000) ──────────────────────────────────────────┐
│                                                                     │
│  getUserMedia ──→ 摄像头预览 + Canvas 截帧 (1fps)                   │
│  getUserMedia ──→ 麦克风 ──→ AudioContext ──→ PCM 24kHz ──→ WAV   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  WebSocket Client                                            │   │
│  │  • frame  →  JPEG base64                                     │   │
│  │  • audio  →  WAV base64                                      │   │
│  │  • text   →  文字输入                                         │   │
│  └──────────────────────────┬───────────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────────────┘
                              │ ws://localhost:8000/ws
                              ▼
┌─ Node.js Server ───────────────────────────────────────────────────┐
│                                                                     │
│  server.js          入口：Express + WebSocketServer                 │
│  websocket_handler  消息路由：frame/audio/text → 对应处理器         │
│  vision_processor   视觉处理：sharp 压缩 → step-3.7-flash 分析      │
│  realtime_handler   实时语音：stepfun-realtime-api WebSocket 客户端  │
│  agent_orchestrator  对话编排（文字聊天备用）                        │
│  audio_processor     HTTP ASR + TTS（备用方案）                     │
│  cost_controller     帧率控制 / 静音检测 / Token 预算               │
│  event_bus           EventEmitter 事件总线                          │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  /api/health         健康检查                                 │   │
│  │  /api/admin/stream   SSE 管理端事件流                         │   │
│  │  /admin              管理端监控页面                            │   │
│  │  /                   Web 客户端                               │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ HTTPS
                               ▼
┌─ 阶跃星辰 API ─────────────────────────────────────────────────────┐
│                                                                     │
│  POST /v1/chat/completions  ─── step-3.7-flash (视觉 + 对话)       │
│  wss://api.stepfun.com/v1/realtime ─── step-1o-audio (实时语音)    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 数据流

### 语音对话（实时）

```
浏览器麦克风 ──→ PCM 24kHz ──→ WAV base64 ──WebSocket──→ 后端
                                                           │
                                            extractPCMFromWAV()
                                                           │
                                           realtimeClient.appendInputAudio()
                                                           │
                                         阶跃星辰 Realtime WS ──→ VAD 检测
                                                           │     ├─ speech_start
                                                           │     ├─ ASR 转文字
                                                           │     ├─ LLM 推理
                                                           │     └─ TTS 合成
                                                           │
                      浏览器 ←──WebSocket── 后端 ←──── 事件回调
                      ├─ user_message     (用户语音文本)
                      ├─ assistant_message (AI 回复文本)
                      └─ audio_output     (AI 语音 PCM)
```

### 视觉分析

```
浏览器摄像头 ──→ Canvas 截帧 ──→ JPEG base64 ──WebSocket──→ 后端
                                                              │
                                               sharp 压缩至 512px
                                                              │
                                          step-3.7-flash Vision API
                                                              │
                      浏览器 ←──WebSocket── frame_analyzed (画面描述)
```

## 目录结构

```
qiniu/
├── server.js                 # 服务入口
├── realtime_handler.js       # 阶跃星辰实时语音 WebSocket 客户端
├── vision_processor.js       # 摄像头帧 → Vision API
├── audio_processor.js        # HTTP ASR + TTS（备用）
├── agent_orchestrator.js     # 文字对话编排
├── cost_controller.js        # 帧率/静音/Token 控制
├── websocket_handler.js      # WebSocket 会话管理
├── event_bus.js              # 事件总线（SSE + 跨模块通信）
├── .env                      # 环境变量（API Key 等）
├── .env.example              # 环境变量模板
├── package.json
└── public/
    ├── index.html            # Web 客户端
    ├── style.css             # 样式（暗色主题）
    ├── app.js                # 前端逻辑（摄像头/麦克风/WebSocket）
    └── admin.html            # 管理端监控页面
```

## 快速启动

```bash
# 1. 安装依赖
npm install

# 2. 配置 API Key
cp .env.example .env
# 编辑 .env，填入 STEPFUN_API_KEY=你的密钥

# 3. 启动
npm start

# 4. 浏览器打开
# 主应用:    http://localhost:8000
# 管理端:    http://localhost:8000/admin
# 健康检查:  http://localhost:8000/api/health
```

- **有 API Key** → full 模式，真实 AI 实时语音对话
- **无 API Key** → demo 模式，mock 回复

## 页面说明

| 地址 | 用途 |
|------|------|
| `/` | 用户对话界面——摄像头全屏背景 + 对话气泡 + 底部控制 |
| `/admin` | 管理端——实时监控麦克风输入、AI 回复、画面分析、在线会话 |

## 配置项

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `STEPFUN_API_KEY` | - | 阶跃星辰 API Key（必填） |
| `STEPFUN_BASE_URL` | `https://api.stepfun.com/v1` | API 地址 |
| `VISION_MODEL` | `step-3.7-flash` | 视觉理解模型 |
| `CHAT_MODEL` | `step-3.7-flash` | 文字对话模型 |
| `MAX_FPS` | `1.0` | 视频帧最大采样率 |
| `MIN_FPS` | `0.2` | 静态场景最小采样率 |
| `SILENCE_THRESHOLD` | `500` | 静音检测 RMS 阈值 |
| `MAX_TOKENS` | `4096` | 对话 Token 预算 |
| `FRAME_RESIZE` | `512` | 画面压缩边长 |
| `JPEG_QUALITY` | `70` | JPEG 压缩质量 |
| `AUDIO_SAMPLE_RATE` | `24000` | 音频采样率（Hz） |
| `PORT` | `8000` | 服务端口 |
