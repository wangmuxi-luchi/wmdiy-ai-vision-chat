/**
 * 阶跃星辰实时语音处理器
 * 使用 stepfun-realtime-api WebSocket 直连，内置 VAD + ASR + LLM + TTS
 */

const { RealtimeClient, ServerEventType } = require('stepfun-realtime-api');
const EventBus = require('./event_bus');

const REALTIME_URL = 'wss://api.stepfun.com/v1/realtime';
const MODEL = 'step-1o-audio'; // 稳定成熟的实时语音模型

class RealtimeManager {
  constructor(sessionId, apiKey) {
    this.sessionId = sessionId;
    this.client = new RealtimeClient({
      url: REALTIME_URL,
      secret: apiKey,
    });
    this.connected = false;
    this.audioBuffer = Buffer.alloc(0);
    this.bufferThreshold = 8192 * 2; // 16KB PCM 缓冲区阈值
    
    // 捕获底层 WebSocket 错误，防止进程崩溃
    this.client.on('error', (err) => {
      console.error(`[Realtime] WebSocket 错误 ${sessionId}:`, err.message);
      this.connected = false;
    });
  }

  async connect() {
    console.log(`[Realtime] 连接中... session=${this.sessionId}`);
    
    // 使用 Promise.race 来处理连接超时和错误
    const connectPromise = new Promise((resolve, reject) => {
      // 设置错误监听器
      const errorHandler = (err) => {
        console.error(`[Realtime] WebSocket 错误 ${this.sessionId}:`, err.message);
        this.connected = false;
        reject(err);
      };
      
      // 监听各种错误事件
      this.client.on('error', errorHandler);
      this.client.on('close', (code, reason) => {
        if (!this.connected) {
          errorHandler(new Error(`连接关闭: code=${code}, reason=${reason}`));
        }
      });
      
      // 执行连接
      this.client.connect(MODEL)
        .then(() => {
          this.client.off('error', errorHandler);
          resolve();
        })
        .catch((err) => {
          this.client.off('error', errorHandler);
          errorHandler(err);
        });
    });
    
    // 添加超时
    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error('连接超时'));
      }, 10000); // 10秒超时
    });
    
    try {
      await Promise.race([connectPromise, timeoutPromise]);
    } catch (err) {
      console.error(`[Realtime] 连接失败 ${this.sessionId}:`, err.message);
      throw err;
    }
    console.log(`[Realtime] 已连接`);

    try {
      await this.client.updateSession({
      instructions: `你是AI视觉对话助手。你能通过摄像头看到用户，通过麦克风听到用户。
用中文简洁自然地回应，像朋友聊天一样。2-4句话为宜。`,
      turn_detection: { type: 'server_vad' },
      modalities: ['text', 'audio'],
      input_audio_format: 'pcm16',
      output_audio_format: 'pcm16',
    });

    // --- 用户语音识别 ---
    this.client.on(ServerEventType.ConversationItemInputAudioTranscriptionCompleted, (ev) => {
      const text = ev.transcript || '';
      console.log(`[Realtime] 用户说: "${text}"`);
      EventBus.emit('user_speech', { sessionId: this.sessionId, text, timestamp: Date.now() });
    });

    // 实时识别（流式）
    this.client.on(ServerEventType.ConversationItemInputAudioTranscriptionDelta, (ev) => {
      if (ev.delta) {
        EventBus.emit('user_speech_delta', { sessionId: this.sessionId, delta: ev.delta });
      }
    });

    // --- VAD 事件 ---
    this.client.on(ServerEventType.InputAudioBufferSpeechStarted, () => {
      console.log('[Realtime] 检测到语音开始');
      EventBus.emit('speech_start', { sessionId: this.sessionId, timestamp: Date.now() });
    });

    this.client.on(ServerEventType.InputAudioBufferSpeechStopped, () => {
      console.log('[Realtime] 语音结束');
      EventBus.emit('speech_stop', { sessionId: this.sessionId, timestamp: Date.now() });
    });

    // --- AI 文本回复 ---
    this.client.on(ServerEventType.ResponseAudioTranscriptDone, (ev) => {
      const text = ev.transcript || '';
      console.log(`[Realtime] AI说: "${text}"`);
      EventBus.emit('assistant_reply', { sessionId: this.sessionId, text, timestamp: Date.now() });
    });

    // --- AI 音频回复 ---
    this.client.on(ServerEventType.ResponseAudioDelta, (ev) => {
      if (ev.delta) {
        // delta 是 base64 编码的 PCM 音频
        EventBus.emit('ai_audio', {
          sessionId: this.sessionId,
          audio: ev.delta,
          timestamp: Date.now(),
        });
      }
    });

    // --- 错误 ---
    this.client.on(ServerEventType.Error, (ev) => {
      console.error('[Realtime] 错误:', ev.error?.message || ev.error);
    });

    } catch (err) {
      console.error(`[Realtime] 更新会话失败 ${this.sessionId}:`, err.message);
      this.client.disconnect();
      throw err;
    }

    this.connected = true;
  }

  /**
   * 输入音频数据（PCM 16-bit, 16kHz mono）
   * @param {Buffer|ArrayBuffer} audio - PCM 音频数据
   */
  inputAudio(audio) {
    if (!this.connected) return;
    const buf = Buffer.isBuffer(audio) ? audio : Buffer.from(audio);
    try {
      this.client.appendInputAudio(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
    } catch (err) {
      console.error('[Realtime] 音频输入失败:', err.message);
    }
  }

  disconnect() {
    if (this.client) {
      this.client.disconnect();
    }
    this.connected = false;
    console.log(`[Realtime] 断开: ${this.sessionId}`);
  }
}

// 会话管理
const sessions = new Map();

async function getRealtimeSession(sessionId, apiKey) {
  if (sessions.has(sessionId)) {
    return sessions.get(sessionId);
  }

  const mgr = new RealtimeManager(sessionId, apiKey);
  try {
    await mgr.connect();
  } catch (err) {
    console.error(`[Realtime] 连接失败 ${sessionId}:`, err.message);
    throw err;
  }

  sessions.set(sessionId, mgr);
  return mgr;
}

function removeRealtimeSession(sessionId) {
  const mgr = sessions.get(sessionId);
  if (mgr) {
    mgr.disconnect();
    sessions.delete(sessionId);
  }
}

/**
 * 从 WAV Buffer 提取 PCM 数据
 */
function extractPCMFromWAV(wavBuffer) {
  // WAV header is 44 bytes, followed by PCM 16-bit data
  if (wavBuffer.length < 44) return Buffer.alloc(0);
  return wavBuffer.slice(44);
}

module.exports = {
  RealtimeManager,
  getRealtimeSession,
  removeRealtimeSession,
  extractPCMFromWAV,
};