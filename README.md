# AI 视觉对话助手

基于 Flutter + FastAPI + deepagents + OpenAI 的实时音视频对话应用。

## 架构

```
Flutter App (摄像头+麦克风) ←→ WebSocket ←→ FastAPI (网关) ←→ deepagents (Agent) ←→ OpenAI API (Vision/Whisper/TTS)
```

- **前端**: Flutter (Android/iOS/Web)，负责音视频采集与交互
- **后端**: FastAPI，WebSocket 网关 + 媒体处理管道
- **Agent 层**: deepagents (基于 LangGraph)，AI 推理与多模态融合
- **外部 API**: OpenAI GPT-4 Vision / Whisper / TTS

## 快速开始

### 1. 后端

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 配置 API Key
cp .env.example .env
# 编辑 .env 填入 OPENAI_API_KEY

# 启动
python main.py
# 或: uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### 2. 前端

```bash
cd frontend
flutter pub get
flutter run
```

> **注意**: Android 模拟器默认使用 `10.0.2.2` 访问宿主机 localhost，iOS 模拟器使用 `localhost`。如需修改，编辑 `chat_screen.dart` 中的 WebSocket URL。

### 3. 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENAI_API_KEY` | - | OpenAI API Key（必填） |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | API 基础 URL |
| `MAX_FPS` | `1.0` | 视频帧最大采样率 |
| `SILENCE_THRESHOLD` | `500` | 静音检测阈值 |
| `MAX_TOKENS` | `4096` | 对话 Token 预算 |
| `FRAME_RESIZE` | `512` | 画面压缩尺寸 |

## 成本控制策略

- ✅ 智能帧采样：画面无变化时自动降帧至 0.2 fps
- ✅ 画面压缩：JPEG 压缩 + 分辨率缩放至 640px/512px
- ✅ 静音检测：跳过无语音音频片段的 STT 调用
- ✅ Token 预算管理：超限自动摘要历史对话
- ✅ GPT-4 Vision `low detail` 模式：每帧仅 85 tokens
