/**
 * 阶跃星辰实时语音处理器
 * 使用 stepfun-realtime-api WebSocket 直连，内置 VAD + ASR + LLM + TTS
 */

const { RealtimeClient, ServerEventType } = require('stepfun-realtime-api');
const EventBus = require('./event_bus');

const REALTIME_URL = 'wss://api.stepfun.com/v1/realtime';
const MODEL = 'step-1o-audio'; // 实时语音

class RealtimeManager {
  constructor(sessionId, apiKey) {
    this.sessionId = sessionId;
    this.apiKey = apiKey;
    this.client = null;
    this.connected = false;
    this.audioBuffer = Buffer.alloc(0);
    this.bufferThreshold = 8192 * 2;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 2000;
    this.reconnectTimer = null;
    this._eventHandlers = []; // 保存事件注册，重连后重新绑定
  }

  _createClient() {
    const client = new RealtimeClient({
      url: REALTIME_URL,
      secret: this.apiKey,
    });
    client.on('error', (err) => {
      console.error(`[Realtime] WebSocket 错误 ${this.sessionId}:`, err.message);
      const msg = err.message || '';
      // 空闲超时/服务器错误 不重连（步-1o-audio 自动断开的正常行为）
      if (msg.includes('too long without operation') || msg.includes('server error')) {
        this.connected = false;
        return;
      }
      if (this.connected && msg) {
        this.connected = false;
        this._scheduleReconnect();
      }
    });
    return client;
  }

  async connect() {
    // 已被移除的 session 不再连接
    if (!sessions.has(this.sessionId)) return;
    if (this.reconnectTimer) { clearTimeout(this.reconnectTimer); this.reconnectTimer = null; }
    console.log(`[Realtime] 连接中... session=${this.sessionId}`);
    this.client = this._createClient();

    const connectPromise = new Promise((resolve, reject) => {
      const errorHandler = (err) => {
        console.error(`[Realtime] WebSocket 错误 ${this.sessionId}:`, err.message);
        this.connected = false;
        reject(err);
      };

      this.client.on('error', errorHandler);
      this.client.on('close', (code, reason) => {
        if (!this.connected) {
          errorHandler(new Error(`连接关闭: code=${code}, reason=${reason}`));
        }
      });

      this.client.connect(MODEL)
        .then(() => {
          resolve();
        })
        .catch((err) => {
          errorHandler(err);
        });
    });

    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => reject(new Error('连接超时')), 10000);
    });

    try {
      await Promise.race([connectPromise, timeoutPromise]);
    } catch (err) {
      console.error(`[Realtime] 连接失败 ${this.sessionId}:`, err.message);
      this._scheduleReconnect();
      throw err;
    }
    console.log(`[Realtime] 已连接`);
    this.connected = true;
    this.reconnectAttempts = 0;

    // 提前注册断线监听，防止 _setupSession 期间断开未捕获
    this.client.on('close', (code, reason) => {
      console.log(`[Realtime] 连接断开，准备重连... session=${this.sessionId}`);
      this.connected = false;
      this._scheduleReconnect();
    });

    await this._setupSession();
  }

  async _setupSession() {
    try {
      await this.client.updateSession({
      instructions: `你是AI视觉对话助手。你能通过摄像头看到用户，通过麦克风听到用户。
用中文简洁自然地回应，像朋友聊天一样。1-2句话，尽量简短。`,
      turn_detection: { type: 'server_vad', silence_duration_ms: 200 },
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

    // --- AI 文本回复（流式）---
    this.client.on(ServerEventType.ResponseAudioTranscriptDelta, (ev) => {
      if (ev.delta) {
        EventBus.emit('ai_text_delta', { sessionId: this.sessionId, delta: ev.delta });
      }
    });

    // --- AI 文本回复（完成）---
    this.client.on(ServerEventType.ResponseAudioTranscriptDone, (ev) => {
      const text = ev.transcript || '';
      console.log(`[Realtime] AI说: "${text}"`);
      EventBus.emit('assistant_reply', { sessionId: this.sessionId, text, timestamp: Date.now() });
    });

    // --- AI 音频回复 ---
    this.client.on(ServerEventType.ResponseAudioDelta, (ev) => {
      if (ev.delta) {
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
  }

  _scheduleReconnect() {
    if (!sessions.has(this.sessionId)) return; // 已被移除
    if (this._reconnecting) return; // 防止重连竞态
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error(`[Realtime] 重连失败：已达最大尝试次数 ${this.maxReconnectAttempts}`);
      return;
    }
    this._reconnecting = true;
    const delay = Math.min(this.reconnectDelay * Math.pow(2, this.reconnectAttempts), 30000);
    this.reconnectAttempts++;
    console.log(`[Realtime] 将在 ${delay}ms 后重连 (${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
    this.reconnectTimer = setTimeout(async () => {
      try {
        await this.connect();
        console.log(`[Realtime] 重连成功: ${this.sessionId}`);
      } catch (err) {
        console.error(`[Realtime] 重连失败:`, err.message);
      }
      this._reconnecting = false;
    }, delay);
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

  /**
   * 更新视觉上下文到实时语音会话
   * 模型在下一轮对话中会参考注入的画面信息
   * @param {string} context - 视觉上下文文本
   */
  async updateVisualContext(context) {
    if (!this.connected) return;
    const instructions = `你是AI视觉对话助手。你能看到用户：${context}。用中文简洁回复，1-2句话。`;

    try {
      await this.client.updateSession({ instructions });
      console.log(`[Realtime] 视觉上下文已注入: ${context.substring(0, 60)}...`);
    } catch (err) {
      console.error(`[Realtime] 更新视觉上下文失败:`, err.message);
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

// 会话管理（step-1o-audio 限制 1 个并发连接，同一时刻只保留最新会话）
const sessions = new Map();

async function getRealtimeSession(sessionId, apiKey) {
  // 断开所有旧会话（step-1o-audio 只允许一个并发连接）
  for (const [sid, mgr] of sessions) {
    if (sid !== sessionId) {
      console.log(`[Realtime] 关闭旧会话: ${sid}`);
      mgr._reconnecting = false; // 阻止重连
      mgr.disconnect();
    }
  }
  sessions.clear();

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
    mgr._reconnecting = false;
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