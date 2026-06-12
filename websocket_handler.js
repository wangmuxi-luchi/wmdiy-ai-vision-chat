/**
 * WebSocket 网关 — 会话管理 + 消息路由
 */

const EventBus = require('./event_bus');
const { processFrame, cleanupSession: cleanupVision } = require('./vision_processor');
const { processAudioChunk, synthesizeSpeech, cleanupSession: cleanupAudio } = require('./audio_processor');
const { processUserInput, chatText, updateFrameDescription, cleanupSession: cleanupAgent } = require('./agent_orchestrator');

/**
 * 连接管理器
 */
class ConnectionManager {
  constructor() {
    this.connections = new Map(); // sessionId → WebSocket
  }

  connect(sessionId, ws) {
    this.connections.set(sessionId, ws);
    console.log(`[WS] 连接: ${sessionId} (在线: ${this.connections.size})`);
  }

  disconnect(sessionId) {
    this.connections.delete(sessionId);
    cleanupVision(sessionId);
    cleanupAudio(sessionId);
    cleanupAgent(sessionId);
    console.log(`[WS] 断开: ${sessionId} (在线: ${this.connections.size})`);
  }

  get(sessionId) {
    return this.connections.get(sessionId);
  }

  sendJson(sessionId, data) {
    const ws = this.connections.get(sessionId);
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify(data));
    }
  }

  sendBytes(sessionId, data) {
    const ws = this.connections.get(sessionId);
    if (ws && ws.readyState === 1) {
      ws.send(data);
    }
  }

  /** 当前在线数 */
  get onlineCount() {
    return this.connections.size;
  }

  /** 所有 session ID */
  get sessionIds() {
    return Array.from(this.connections.keys());
  }
}

/**
 * 创建 WebSocket 处理器
 * @param {object} openaiClient - OpenAI 客户端（可能为 null）
 * @param {boolean} apiAvailable - API 是否可用
 * @returns {{ manager: ConnectionManager, handleConnection: Function }}
 */
function createWebSocketHandler(openaiClient, apiAvailable) {
  const manager = new ConnectionManager();

  async function handleConnection(ws, sessionId) {
    manager.connect(sessionId, ws);

    // 通知管理端
    EventBus.emit('session_connected', {
      sessionId,
      onlineCount: manager.onlineCount,
      timestamp: Date.now(),
    });

    // 发送连接确认
    manager.sendJson(sessionId, {
      type: 'connected',
      session_id: sessionId,
      mode: apiAvailable ? 'full' : 'demo',
      timestamp: Date.now(),
    });

    ws.on('message', async (raw) => {
      let msg;
      try {
        const str = Buffer.isBuffer(raw) ? raw.toString() : raw instanceof ArrayBuffer ? Buffer.from(raw).toString() : String(raw);
        msg = JSON.parse(str);
      } catch {
        console.warn(`[WS] 无法解析消息: ${sessionId}`);
        return;
      }

      try {
        await routeMessage(sessionId, msg);
      } catch (err) {
        console.error(`[WS] 消息处理错误 ${sessionId}:`, err.message);
      }
    });

    ws.on('close', () => {
      manager.disconnect(sessionId);
      EventBus.emit('session_disconnected', {
        sessionId,
        onlineCount: manager.onlineCount,
        timestamp: Date.now(),
      });
    });

    ws.on('error', (err) => {
      console.error(`[WS] 错误 ${sessionId}:`, err.message);
      manager.disconnect(sessionId);
    });
  }

  /**
   * 消息路由
   */
  async function routeMessage(sessionId, msg) {
    const { type } = msg;

    switch (type) {
      case 'ping':
        manager.sendJson(sessionId, { type: 'pong', timestamp: Date.now() });
        break;

      case 'frame':
        await handleFrame(sessionId, msg.data);
        break;

      case 'audio':
        await handleAudio(sessionId, msg.data);
        break;

      case 'test_chat':
        await handleTextChat(sessionId, msg.data);
        break;

      case 'control':
        manager.sendJson(sessionId, {
          type: 'control_ack',
          command: msg.command,
          timestamp: Date.now(),
        });
        break;

      default:
        console.warn(`[WS] 未知消息类型: ${type}`);
    }
  }

  /**
   * 处理视频帧
   */
  async function handleFrame(sessionId, base64Jpeg) {
    try {
      const result = await processFrame(openaiClient, sessionId, base64Jpeg, apiAvailable);

      if (result.description) {
        updateFrameDescription(sessionId, result.description);

        manager.sendJson(sessionId, {
          type: 'frame_analyzed',
          description: result.description,
          timestamp: Date.now(),
        });

        // → 管理端
        EventBus.emit('frame_analyzed', {
          sessionId,
          description: result.description,
          timestamp: Date.now(),
        });
      }
    } catch (err) {
      console.error(`[Frame] 处理失败 ${sessionId}:`, err.message);
    }
  }

  /**
   * 处理音频
   */
  async function handleAudio(sessionId, base64Audio) {
    console.log(`[WS] 收到音频: ${sessionId}, base64 长度=${(base64Audio || '').length}`);
    try {
      const result = await processAudioChunk(
        openaiClient,
        sessionId,
        base64Audio,
        apiAvailable,
        (userText) => {
          console.log(`[WS] 语音识别结果: "${userText}"`);
          manager.sendJson(sessionId, {
            type: 'user_message',
            text: userText,
            timestamp: Date.now(),
          });
        }
      );

      console.log(`[WS] 音频处理结果: skipped=${result.skipped}, userText="${(result.userText || '').substring(0, 40)}"`);

      if (result.skipped) return;

      if (result.userText && result.needsAgentResponse !== false) {
        // → 管理端：用户语音
        EventBus.emit('user_speech', {
          sessionId,
          text: result.userText,
          timestamp: Date.now(),
        });

        const aiText = await processUserInput(openaiClient, sessionId, result.userText, apiAvailable);

        manager.sendJson(sessionId, {
          type: 'assistant_message',
          text: aiText,
          timestamp: Date.now(),
        });

        // → 管理端：AI 回复
        EventBus.emit('assistant_reply', {
          sessionId,
          text: aiText,
          timestamp: Date.now(),
        });

        if (apiAvailable && aiText) {
          try {
            const ttsBuffer = await synthesizeSpeech(openaiClient, aiText);
            manager.sendBytes(sessionId, ttsBuffer);
          } catch (ttsErr) {
            console.error(`[TTS] 合成失败 ${sessionId}:`, ttsErr.message);
          }
        }
      }
    } catch (err) {
      console.error(`[Audio] 处理失败 ${sessionId}:`, err.message);
    }
  }

  /**
   * 处理文字聊天（Web 客户端）
   */
  async function handleTextChat(sessionId, text) {
    if (!text || text.trim().length === 0) return;

    manager.sendJson(sessionId, {
      type: 'user_message',
      text: text,
      timestamp: Date.now(),
    });

    // → 管理端
    EventBus.emit('user_speech', {
      sessionId,
      text,
      timestamp: Date.now(),
    });

    const aiText = await chatText(openaiClient, sessionId, text, apiAvailable);

    manager.sendJson(sessionId, {
      type: 'assistant_message',
      text: aiText,
      timestamp: Date.now(),
    });

    // → 管理端
    EventBus.emit('assistant_reply', {
      sessionId,
      text: aiText,
      timestamp: Date.now(),
    });

    if (apiAvailable && aiText) {
      try {
        const ttsBuffer = await synthesizeSpeech(openaiClient, aiText);
        manager.sendBytes(sessionId, ttsBuffer);
      } catch (ttsErr) {
        console.error(`[TTS] 合成失败 ${sessionId}:`, ttsErr.message);
      }
    }
  }

  return { manager, handleConnection };
}

module.exports = { ConnectionManager, createWebSocketHandler };
