# 前端项目文件说明

## 📁 项目结构

```
lib/
├── main.dart                    # 应用入口
├── env.dart                     # 环境变量配置
├── chat_screen.dart             # 主聊天界面
├── services/                    # 服务层
│   ├── locator.dart             # 依赖注入配置
│   ├── communication_service.dart        # 通信服务接口
│   ├── camera_service.dart               # 摄像头服务接口
│   ├── camera_image_service.dart         # 图像服务接口
│   ├── command_receiver_service.dart     # 命令接收服务接口
│   ├── message_receiver_service.dart     # 消息接收服务接口
│   ├── text_processor_service.dart       # 文本处理服务接口
│   ├── speech_recognition_service.dart   # 语音识别服务接口
│   └── impl/                    # 服务实现
│       ├── web_socket_communication_service.dart
│       ├── camera_service_impl.dart
│       ├── command_receiver_service_impl.dart
│       ├── message_receiver_service_impl.dart
│       ├── backend_text_processor_service.dart
│       ├── asr_speech_recognition_service.dart
│       ├── mock_communication_service.dart
│       ├── mock_camera_service.dart
│       ├── mock_camera_image_service.dart
│       ├── mock_command_receiver_service.dart
│       └── mock_message_receiver_service.dart
└── utils/                       # 工具类
    └── logger.dart              # 日志工具
```

---

## 🎯 文件功能详解

### 1. 入口文件

| 文件 | 功能 | 说明 |
|------|------|------|
| `main.dart` | 应用入口 | 初始化环境变量，启动应用 |
| `env.dart` | 环境变量配置 | 存储全局环境变量常量 |

### 2. UI 层

| 文件 | 功能 | 说明 |
|------|------|------|
| `chat_screen.dart` | 主聊天界面 | 包含摄像头预览、消息列表、输入框等核心UI |

### 3. 依赖注入配置

| 文件 | 功能 | 说明 |
|------|------|------|
| `locator.dart` | GetIt依赖注入配置 | 注册所有服务，支持Mock模式切换 |

### 4. 服务接口定义

| 文件 | 功能 | 核心方法 |
|------|------|----------|
| `communication_service.dart` | 通信服务接口 | `connect()`, `sendTextMessage()`, `sendImage()` |
| `camera_service.dart` | 摄像头服务接口 | `initialize()`, `captureImage()`, `switchCamera()` |
| `camera_image_service.dart` | 图像分析服务接口 | `analyzeImage()` |
| `command_receiver_service.dart` | 命令接收服务接口 | `commandStream` |
| `message_receiver_service.dart` | 消息接收服务接口 | `receiveMessage()` |
| `text_processor_service.dart` | 文本处理服务接口 | `processText()` |
| `speech_recognition_service.dart` | 语音识别服务接口 | `startListening()`, `stopListening()` |

### 5. 服务实现（真实）

| 文件 | 功能 | 依赖 |
|------|------|------|
| `web_socket_communication_service.dart` | WebSocket通信实现 | web_socket_channel |
| `camera_service_impl.dart` | 摄像头功能实现 | camera |
| `command_receiver_service_impl.dart` | 命令接收实现 | 解析WebSocket消息 |
| `message_receiver_service_impl.dart` | 消息接收实现 | 监听WebSocket消息 |
| `backend_text_processor_service.dart` | 后端文本处理 | 调用通信服务 |
| `asr_speech_recognition_service.dart` | 语音识别实现 | 腾讯云ASR插件 |

### 6. 服务实现（Mock）

| 文件 | 功能 | 使用场景 |
|------|------|----------|
| `mock_communication_service.dart` | Mock通信服务 | 离线测试 |
| `mock_camera_service.dart` | Mock摄像头服务 | 无硬件测试 |
| `mock_camera_image_service.dart` | Mock图像服务 | 离线测试 |
| `mock_command_receiver_service.dart` | Mock命令服务 | 离线测试 |
| `mock_message_receiver_service.dart` | Mock消息服务 | 离线测试 |

### 7. 工具类

| 文件 | 功能 | 特性 |
|------|------|------|
| `logger.dart` | 日志工具类 | 支持调试/错误/警告级别，生产环境可关闭 |

---

## 🔄 核心数据流

```
用户操作 → UI层 → 服务层 → 后端
     ↓
   响应 ← 服务层 ← WebSocket/API
```

### 消息发送流程
```
用户输入 → chat_screen → communication_service → WebSocket → 后端
```

### 消息接收流程
```
后端 → WebSocket → communication_service → message_receiver_service → chat_screen → UI更新
```

### 图像发送流程
```
用户点击 → chat_screen → camera_service.captureImage() → communication_service.sendImage() → 后端
```

---

## 🚀 启动方式

```bash
# 开发模式（使用真实服务）
flutter run

# 测试模式（使用Mock服务）
flutter run --dart-define=USE_MOCK=true

# 指定后端地址
flutter run --dart-define=BACKEND_HOST=192.168.1.100 --dart-define=BACKEND_PORT=8000
```

---

## 📊 服务依赖关系

```
chat_screen
    ├── speech_recognition_service
    ├── text_processor_service
    ├── message_receiver_service
    │       └── communication_service
    ├── command_receiver_service
    │       └── communication_service
    ├── camera_image_service
    ├── camera_service
    └── communication_service
            └── WebSocket
```

---

## 📝 代码规范

- **命名规范**：小驼峰命名法（camelCase）
- **文件结构**：按功能模块划分目录
- **依赖注入**：统一使用 GetIt 管理服务
- **日志记录**：统一使用 Logger 工具类
- **错误处理**：关键操作需进行 try-catch 处理