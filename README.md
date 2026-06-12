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
| **Web 前端** | 原生 HTML/CSS/JS | 无框架，浏览器 Web API |
| **Flutter 前端** | Flutter 3.19+ | 跨平台移动应用（iOS/Android） |

### Flutter 前端技术栈

| 功能 | 技术/包 | 说明 |
|------|---------|------|
| **状态管理** | GetIt | 依赖注入和服务定位 |
| **语音识别** | asr_plugin | 腾讯云 ASR 语音转文字 |
| **WebSocket** | web_socket_channel | WebSocket 通信 |
| **摄像头** | camera | 相机预览和拍照 |
| **环境变量** | flutter_dotenv | .env 配置管理 |
| **日志** | logger | 结构化日志输出 |

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
wmdiy-ai-vision-chat/
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
├── public/                   # Web 前端（原生 HTML/CSS/JS）
│   ├── index.html            # Web 客户端
│   ├── style.css             # 样式（暗色主题）
│   ├── app.js                # 前端逻辑（摄像头/麦克风/WebSocket）
│   └── admin.html            # 管理端监控页面
├── frontend_kotlin/          # Flutter 跨平台前端
│   ├── lib/
│   │   ├── chat_screen.dart  # 聊天主界面
│   │   ├── main.dart         # 应用入口
│   │   ├── services/         # 服务层
│   │   ├── widgets/          # UI 组件
│   │   └── utils/            # 工具类
│   ├── test/                 # 单元测试
│   ├── .env                  # Flutter 环境变量
│   └── pubspec.yaml          # 依赖配置
└── agent/                    # 设计文档
    └── ...
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

---

## Flutter 前端（frontend_kotlin）

### 功能特点

| 功能 | 说明 |
|------|------|
| **语音转文字** | 腾讯云 ASR 实时语音识别 |
| **自动发送** | 支持手动/自动发送切换，说完一段自动发送 |
| **摄像头预览** | 实时相机预览，支持前后置切换 |
| **图片发送** | 手动拍照或自动定时发送图像 |
| **对话气泡** | 消息列表展示，支持滚动查看历史 |
| **侧边栏配置** | 后端服务配置、语音服务配置 |
| **全屏模式** | 相机全屏预览，沉浸式体验 |

### 核心组件

| 文件 | 功能 |
|------|------|
| `chat_screen.dart` | 聊天主界面，包含语音输入、消息展示、相机预览 |
| `main.dart` | 应用入口，全局状态管理和错误处理 |
| `services/speech_recognition_service.dart` | 语音识别服务接口 |
| `services/communication_service.dart` | WebSocket 通信服务 |
| `services/camera_service.dart` | 相机服务 |
| `services/config_service.dart` | 配置管理服务 |
| `widgets/sidebar.dart` | 侧边栏配置面板 |

### 启动方式

```bash
# 1. 进入前端目录
cd frontend_kotlin

# 2. 安装依赖
flutter pub get

# 3. 配置后端地址（可选）
# 编辑 .env 文件设置 BACKEND_HOST
# 或在应用内侧边栏配置

# 4. 运行（确保后端服务已启动）
flutter run

# 5. 构建 APK
flutter build apk --release
```

### 配置说明

**环境变量（`.env`）**：
```env
# WebSocket 服务器配置
BACKEND_HOST=localhost
BACKEND_PORT=8000

# 腾讯云语音识别配置（可选，运行时可配置）
TENCENT_APP_ID=
TENCENT_SECRET_ID=
TENCENT_SECRET_KEY=
```

**运行时配置**：
1. 点击右上角侧边栏按钮
2. 配置后端服务器地址和端口
3. 配置语音识别服务参数
4. 配置自动发送功能

---

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

## 配网操作指南

### 一、确定后端服务器 IP 地址

#### 1. 获取电脑的局域网 IP

**Windows 系统：**
```cmd
ipconfig
```
找到 `IPv4 地址`，通常格式为 `192.168.x.x` 或 `10.x.x.x`

**macOS/Linux 系统：**
```bash
ifconfig
# 或
ip addr
```
找到 `inet` 字段，排除 `127.0.0.1` 的地址

#### 2. 验证服务监听状态

启动后端服务后，检查服务是否正常监听：
```bash
# 服务启动日志应显示：
# 地址: http://localhost:8000
# 局域网: http://192.168.x.x:8000  (如果配置了自动获取)
```

**重要说明：**
- 服务实际监听地址是 `0.0.0.0:8000`（所有网络接口）
- `localhost:8000` 仅能在本机访问
- 其他设备（手机/平板）需使用局域网 IP 访问

---

### 二、配置前端连接地址

#### 方式一：修改环境变量（推荐）

编辑 `frontend_kotlin/.env` 文件：
```env
# WebSocket 服务器配置
BACKEND_HOST=192.168.0.106  # 替换为你的电脑局域网IP
BACKEND_PORT=8000
```

#### 方式二：运行时配置（Flutter 应用）

1. 打开侧边栏 → 点击"后端服务配置"
2. 填写配置信息：
   - **服务器地址**：电脑局域网 IP（如 `192.168.0.106`）
   - **端口号**：`8000`
   - **协议**：`ws`（WebSocket）
3. 点击"保存"，配置立即生效

#### 方式三：ADB 端口转发（开发调试）

如果手机通过 USB 连接电脑，可以使用端口转发：
```bash
adb reverse tcp:8000 tcp:8000
```
这样手机上的 `localhost:8000` 会转发到电脑的 `localhost:8000`

---

### 三、网络连接要求

| 场景 | 要求 | 配置方式 |
|------|------|----------|
| **电脑浏览器访问** | 无需额外配置 | `http://localhost:8000` |
| **手机同WiFi访问** | 手机和电脑在同一局域网 | 使用电脑局域网 IP |
| **USB调试访问** | 手机通过USB连接电脑 | 使用 ADB 端口转发 |
| **公网访问** | 需要端口映射/域名 | 配置路由器端口转发 |

---

### 四、常见问题排查

**1. 手机无法连接后端**
- ✅ 确认手机和电脑在**同一 WiFi 网络**
- ✅ 确认电脑防火墙允许 **8000 端口**
- ✅ 确认使用的是**电脑局域网 IP**，不是 `localhost`

**2. 连接被拒绝**
- ✅ 确认后端服务正在运行
- ✅ 确认端口号正确（默认 `8000`）
- ✅ 确认服务器 IP 无误

**3. 配置不生效**
- ✅ Flutter 应用：修改配置后点击"保存"
- ✅ Web 应用：修改 `.env` 后重启服务
- ✅ 清理应用缓存后重试

---

### 五、配置验证

启动服务后，可通过以下方式验证：

```bash
# 检查服务是否运行
curl http://localhost:8000/api/health
# 响应示例：{"status":"ok","mode":"demo","timestamp":...}

# 从其他设备测试连接
# 替换为你的实际IP
curl http://192.168.0.106:8000/api/health
```