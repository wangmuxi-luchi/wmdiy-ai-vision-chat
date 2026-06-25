# CLAUDE.md

## Project

Caibao — AI 视觉对话助手 (AI Vision Chat Assistant). 浏览器端实时 AI 视觉对话应用：摄像头 + 麦克风输入，AI 以语音回复。基于阶跃星辰 (StepFun) 多模态 API 的 Node.js 全栈应用。

## Commands

```bash
npm install          # 安装依赖
cp .env.example .env # 配置环境变量（填入 STEPFUN_API_KEY）
npm start            # 生产模式 (node server.js)，监听 0.0.0.0:8000
npm run dev          # 开发模式 (node --watch server.js)，自动重启
```

## Architecture

```
Browser ──WebSocket (/ws)──→ Node.js Server ──→ StepFun API
   ├─ 摄像头帧 (JPEG base64, 1fps)
   ├─ 麦克风 PCM (24kHz, 3s chunks)
   └─ 文字聊天
```

单进程 Node.js，Express 静态服务 + WebSocket。前端纯原生 HTML/CSS/JS (`public/`)。

### 核心模块

| 文件 | 职责 |
|------|------|
| `server.js` | 入口：Express + WebSocket 服务器，路由消息 |
| `realtime_handler.js` | 阶跃星辰实时语音 WebSocket 客户端 (`step-1o-audio`) |
| `vision_processor.js` | 摄像头帧压缩 + 视觉 API 分析 (`step-3.7-flash`) |
| `audio_processor.js` | HTTP ASR + TTS 备用管道 |
| `agent_orchestrator.js` | 对话编排、历史管理、Token 预算 |
| `cost_controller.js` | 帧率控制、静音检测、Token 预算 |
| `websocket_handler.js` | WebSocket 会话管理 + 消息路由 |
| `event_bus.js` | EventEmitter 单例，松耦合事件分发 |

### 双模式运行

- **完整模式**：配置有效 `STEPFUN_API_KEY`，调用真实 AI API
- **演示模式**：无 API Key，返回 mock 数据

### 双通道音频

- **实时路径**：`stepfun-realtime-api` SDK → WebSocket 直连，集成 VAD + ASR + LLM + TTS
- **备用路径**：HTTP ASR → 对话编排 → HTTP TTS

### 事件系统

`EventBus` (EventEmitter 单例) 广播 `session_connected`、`user_speech`、`assistant_reply`、`frame_analyzed` 等事件 → 管理面板通过 SSE (`/api/admin/stream`) 实时接收。

### 三层成本控制

1. 帧率动态调节 (0.2–1.0 fps，基于帧哈希静止检测)
2. 静音跳过 (PCM RMS 阈值 500)
3. Token 预算 (默认 4096，超 80% 触发对话摘要)

## Key Patterns

- 前后端通过单一 WebSocket 通信，消息协议深度耦合
- 每个 WS 连接对应一个 `RealtimeManager` 实例和会话状态
- 所有会话状态存储在 `ConnectionManager` 的 Map 中
- 环境变量统一从 `.env` 加载 (`dotenv`)
- 无测试框架、无 TypeScript、无构建工具 — 原生 Node.js

## Routes

- `GET /` — Web 客户端
- `GET /admin` — 管理监控面板
- `GET /api/health` — 健康检查
- `GET /api/admin/stream` — 管理端 SSE 事件流
- `WS /ws` — 客户端 WebSocket
