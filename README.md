# AI 视觉对话助手

AI 通过摄像头看到你，通过麦克风听到你，实时语音对话。

**在线演示**：`https://124.221.110.20`（腾讯云 + HTTPS）

---

## 架构

```
浏览器 ──WebSocket──→ Node.js ──HTTP──→ 阶跃星辰 API
  │                      │
  ├─ 摄像头 (按需截图)    ├─ 自研静音检测（PCM RMS）
  ├─ 麦克风 (PCM 24kHz)   ├─ HTTP ASR（stepaudio-2.5-asr）
  └─ 文字聊天             ├─ Agent 编排（step-3.7-flash + 视觉上下文）
                          └─ HTTP TTS（step-tts-mini）
```

### 数据流

```
你说完话 → 350ms 静音判定 → HTTP ASR 转文字 → step-3.7-flash 推理（文字 + 画面）
         → 回复文字 → HTTP TTS 合成语音 → WebSocket 发回浏览器
```

---

## 技术栈

| 层 | 技术 |
|------|------|
| 运行时 | Node.js 20+ |
| HTTP | Express 4.x |
| WebSocket | ws 8.x |
| AI SDK | openai 4.x（OpenAI 兼容协议） |
| 图片处理 | sharp 0.33 |

### AI 模型

| 功能 | 模型 | 接口 |
|------|------|------|
| 语音识别 | `stepaudio-2.5-asr` | HTTP REST |
| 多模态推理 | `step-3.7-flash` | HTTP REST（256K 上下文，图文理解） |
| 语音合成 | `step-tts-mini` | HTTP REST（MP3 输出） |

### 前端

| 端 | 技术 | 说明 |
|------|------|------|
| Web | 原生 HTML/CSS/JS | 摄像头 + 麦克风 + WebSocket |
| Flutter | Flutter 3.19+ | 腾讯云 ASR，跨平台 |

---

## 快速启动

```bash
npm install
cp .env.example .env    # 填入 STEPFUN_API_KEY
npm start               # http://localhost:8000
```

---

## 目录结构

```
├── server.js              # 服务入口（Express + WebSocket + HTTP 音频管线）
├── agent_orchestrator.js  # Agent 编排（step-3.7-flash + 视觉上下文 + Token 预算）
├── audio_processor.js     # HTTP ASR + TTS
├── vision_processor.js    # 帧压缩 + Vision API
├── scene_memory.js        # 视觉场景缓存
├── cost_controller.js     # 静音检测 / Token 控制
├── event_bus.js           # 事件总线
├── websocket_handler.js   # WebSocket 会话管理
├── realtime_handler.js    # 实时语音 WebSocket 客户端（已弃用）
├── public/                # Web 前端
│   ├── index.html
│   ├── style.css
│   └── app.js
├── frontend_kotlin/       # Flutter 前端
└── package.json
```

---

## 核心技术

| 技术 | 说明 |
|------|------|
| **自研音频管线** | PCM RMS 静音检测 → 350ms 判定说完 → HTTP ASR + TTS |
| **多模态 Agent** | step-3.7-flash 图文融合推理，对话历史 + Token 预算管理 |
| **按需截图** | 语音触发截图，不持续占用主线程 |
| **WebSocket 全链路** | JSON + Binary 音频同通道，nginx 反向代理 + HTTPS |

---

## 页面

| 地址 | 用途 |
|------|------|
| `/` | 用户对话界面 |
| `/admin` | 管理端监控 |
| `/api/health` | 健康检查 |
| `/api/admin/stream` | SSE 事件流 |

---

## 配置项

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `STEPFUN_API_KEY` | - | 必填 |
| `STEPFUN_BASE_URL` | `https://api.stepfun.com/v1` | API 地址 |
| `ASR_MODEL` | `stepaudio-2.5-asr` | 语音识别模型 |
| `VISION_MODEL` | `step-3.7-flash` | 视觉/对话模型 |
| `TTS_MODEL` | `step-tts-mini` | 语音合成模型 |
| `PORT` | `8000` | 服务端口 |

---

## 部署

腾讯云 Ubuntu 22.04 + nginx + PM2 + HTTPS。

```bash
# 服务器
scp -i key.pem server.js ... ubuntu@124.221.110.20:/home/ubuntu/ai-vision-web/
ssh ubuntu@124.221.110.20
pm2 restart ai-vision-web
```

---

## 许可证

MIT
