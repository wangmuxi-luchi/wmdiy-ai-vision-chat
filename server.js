/**
 * AI 视觉对话助手 — 服务入口
 */

require('dotenv').config();

// ── 时间戳日志 ──
const _ts = () => new Date().toISOString().replace('T', ' ').replace('Z', '');

const _origConsoleLog = console.log;
const _origConsoleError = console.error;
const _origConsoleWarn = console.warn;
const _origConsoleDebug = console.debug;

console.log = function(...args) {
  const msg = String(args[0] || '');
  if (msg === 'proxy' || msg === 'STEP_API') return;
  _origConsoleLog.apply(console, [`[${_ts()}]`, ...args]);
};

console.error = function(...args) {
  _origConsoleError.apply(console, [`[${_ts()}]`, ...args]);
};

console.warn = function(...args) {
  _origConsoleWarn.apply(console, [`[${_ts()}]`, ...args]);
};

console.debug = function(...args) {
  _origConsoleDebug.apply(console, [`[${_ts()}]`, ...args]);
};

// ── 全局异常处理 ──
process.on('uncaughtException', (err) => {
  console.error('[ERROR] 未捕获的异常:', err.message);
  console.error(err.stack);
  // 不退出进程，保持服务运行
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('[ERROR] 未处理的 Promise 拒绝:', reason?.message || reason);
  // 不退出进程，保持服务运行
});

const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const OpenAI = require('openai');
const path = require('path');
const sharp = require('sharp');
const EventBus = require('./event_bus');
const { getRealtimeSession, removeRealtimeSession, extractPCMFromWAV } = require('./realtime_handler');
const { processUserInput, updateFrameDescription, cleanupSession } = require('./agent_orchestrator');

const VISION_MODEL = process.env.VISION_MODEL || 'step-3.7-flash';

const PORT = parseInt(process.env.PORT || '8000', 10);
const STEPFUN_API_KEY = process.env.STEPFUN_API_KEY || '';
const STEPFUN_BASE_URL = process.env.STEPFUN_BASE_URL || 'https://api.stepfun.com/v1';

// 图像和文本可分别配置不同模型
const VISION_API_KEY = process.env.VISION_API_KEY || STEPFUN_API_KEY;
const VISION_BASE_URL = process.env.VISION_BASE_URL || STEPFUN_BASE_URL;
const CHAT_API_KEY = process.env.CHAT_API_KEY || STEPFUN_API_KEY;
const CHAT_BASE_URL = process.env.CHAT_BASE_URL || STEPFUN_BASE_URL;

// 验证 API Key 是否有效
const isValidApiKey = STEPFUN_API_KEY && 
  STEPFUN_API_KEY !== 'your_api_key' && 
  STEPFUN_API_KEY !== 'your_api_key_here' && 
  STEPFUN_API_KEY.length > 10 &&
  /^[a-zA-Z0-9]+$/.test(STEPFUN_API_KEY); // 验证格式（兼容阶跃星辰 Key）

const API_OK = isValidApiKey;

let openaiClient = null;
let visionClient = null;
let chatClient = null;
if (API_OK) {
  openaiClient = new OpenAI({ apiKey: STEPFUN_API_KEY, baseURL: STEPFUN_BASE_URL });
  visionClient = new OpenAI({ apiKey: VISION_API_KEY, baseURL: VISION_BASE_URL });
  chatClient = new OpenAI({ apiKey: CHAT_API_KEY, baseURL: CHAT_BASE_URL });
  console.log('[Init] 阶跃星辰 API 就绪');
  if (VISION_API_KEY !== STEPFUN_API_KEY || VISION_BASE_URL !== STEPFUN_BASE_URL) {
    console.log('[Init] 图像模型独立配置: ' + VISION_BASE_URL);
  }
  if (CHAT_API_KEY !== STEPFUN_API_KEY || CHAT_BASE_URL !== STEPFUN_BASE_URL) {
    console.log('[Init] 文本模型独立配置: ' + CHAT_BASE_URL);
  }
} else {
  console.warn('[Init] 演示模式');
}

// ── Express ──
const app = express();
app.use((req, res, next) => { res.header('Access-Control-Allow-Origin', '*'); res.header('Access-Control-Allow-Headers', '*'); next(); });
app.use(express.static(path.join(__dirname, 'public')));
app.get('/api/health', (_, res) => res.json({ status: 'ok', mode: API_OK ? 'full' : 'demo', timestamp: Date.now() }));
app.get('/', (_, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));
app.get('/admin', (_, res) => res.sendFile(path.join(__dirname, 'public', 'admin.html')));
app.get('/api/admin/stream', sseHandler);

// ── HTTP Server ──
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

// sessionId → ws 映射（用于事件转发）
const sessions = new Map();

wss.on('connection', (ws) => {
  const sid = `s_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  sessions.set(sid, ws);

  console.log(`[WS] 连接: ${sid}`);

  ws.send(JSON.stringify({ type: 'connected', session_id: sid, mode: API_OK ? 'full' : 'demo', timestamp: Date.now() }));
  EventBus.emit('session_connected', { sessionId: sid, timestamp: Date.now() });

  // 初始化实时语音
  let rtMgr = null;
  if (API_OK) {
    getRealtimeSession(sid, STEPFUN_API_KEY)
      .then(m => { rtMgr = m; console.log(`[Realtime] 就绪: ${sid}`); })
      .catch(e => { 
        console.error(`[Realtime] 连接失败: ${sid}`, e.message); 
        console.warn(`[Realtime] 实时语音功能不可用，将进入演示模式`);
        rtMgr = null;
      });
  }

  ws.on('message', async (raw) => {
    // 先尝试解析 JSON（Flutter 的 web_socket_channel 可能以二进制帧发送文本消息）
    if (Buffer.isBuffer(raw)) {
      try {
        const maybeJson = JSON.parse(raw.toString());
        if (maybeJson && maybeJson.type) {
          await handleJsonMessage(maybeJson, sid, ws, rtMgr);
          return;
        }
      } catch {}
      // 非 JSON 二进制 → 音频数据（WAV PCM）
      handleAudioBinary(sid, raw, rtMgr, ws);
      return;
    }

    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch { return; }

    await handleJsonMessage(msg, sid, ws, rtMgr);
  });

  ws.on('close', () => {
    sessions.delete(sid);
    cleanupSession(sid);
    if (rtMgr) { rtMgr.disconnect(); removeRealtimeSession(sid); }
    EventBus.emit('session_disconnected', { sessionId: sid, timestamp: Date.now() });
    console.log(`[WS] 断开: ${sid}`);
  });
});

// ── JSON 消息路由 ──
async function handleJsonMessage(msg, sid, ws, rtMgr) {
  try {
    switch (msg.type) {
      case 'ping':
        ws.send(JSON.stringify({ type: 'pong' }));
        break;
      case 'frame':
        console.log(`[Frame] 收到图像数据: ${sid} | Base64长度: ${msg.data?.length || 0}`);
        await handleFrame(sid, msg.data, ws);
        break;
      case 'audio':
        console.log(`[Audio] 收到音频数据: ${sid} | Base64长度: ${msg.data?.length || 0}`);
        handleAudio(sid, msg.data, rtMgr, ws);
        break;
      case 'test_chat':
      case 'text':
      case 'speech':
        console.log(`[Chat] 收到${msg.type === 'speech' ? '语音' : '文本'}消息: ${sid} | 内容: "${msg.data?.substring(0, 50) || ''}${msg.data?.length > 50 ? '...' : ''}"`);
        await handleChat(sid, msg.data, ws);
        break;
      default:
        console.log(`[WS] 未知消息类型: ${sid} | type: ${msg.type}`);
    }
  } catch (e) { console.error(`[WS] 错误:`, e.message); }
}

// ── 帧分析 ──
async function handleFrame(sid, b64, ws) {
  if (!API_OK) {
    ws.send(JSON.stringify({ type: 'frame_analyzed', description: '[Demo] 画面', timestamp: Date.now() }));
    return;
  }
  try {
    const buf = Buffer.from(b64, 'base64');
    const resized = await sharp(buf).resize(512, 512, { fit: 'inside' }).jpeg({ quality: 70 }).toBuffer();
    console.log(`[Frame] 图像压缩完成: ${sid} | 压缩后大小: ${resized.length} 字节`);
    
    const start = Date.now();
    console.log(`[Frame] 开始调用视觉模型: ${sid} | 模型: ${VISION_MODEL}`);
    const r = await Promise.race([
      visionClient.chat.completions.create({
        model: VISION_MODEL,
        messages: [{
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${resized.toString('base64')}` } },
            { type: 'text', text: '简单描述画面内容，一句话即可。' },
          ],
        }],
        max_tokens: 300,
      }),
      new Promise((_, reject) => setTimeout(() => reject(new Error('视觉模型调用超时（30秒）')), 30000)),
    ]);
    const elapsed = Date.now() - start;
    const desc = r.choices[0]?.message?.content || '分析中...';
    console.log(`[Frame] ${sid} 分析完成 (${elapsed}ms): ${desc.substring(0, 50)}`);
    updateFrameDescription(sid, desc);
    ws.send(JSON.stringify({ type: 'frame_analyzed', description: desc, timestamp: Date.now() }));
    EventBus.emit('frame_analyzed', { sessionId: sid, description: desc, timestamp: Date.now() });
  } catch (e) { 
    console.error('[Frame] 分析失败:', e.message); 
    const response = '分析失败: ' + e.message;
    ws.send(JSON.stringify({ type: 'frame_analyzed', description: response, timestamp: Date.now() }));
  }
}

// ── 实时音频（二进制 WAV → 阶跃星辰 Realtime）──
function handleAudioBinary(sid, wavBuffer, rtMgr, ws) {
  if (!rtMgr?.connected) return;
  try {
    // 存 .wav 方便调试回听
    const fs = require('fs');
    const tmp = `tmp/${sid}_${Date.now()}.wav`;
    fs.mkdirSync('tmp', { recursive: true });
    fs.writeFileSync(tmp, wavBuffer);
    // 去 WAV 头取 PCM → 直喂阶跃星辰
    const pcm = extractPCMFromWAV(wavBuffer);
    if (pcm.length > 0) rtMgr.inputAudio(pcm);
  } catch (e) { console.error('[Audio]', e.message); }
}

// ── 文字聊天 ──
async function handleChat(sid, text, ws) {
  if (!text?.trim()) {
    console.log(`[Chat] 空消息跳过: ${sid}`);
    return;
  }
  
  console.log(`[Chat] 收到用户消息: ${sid} | 内容: "${text}"`);
  console.log(`[Chat] chatClient=${!!chatClient}, API_OK=${API_OK}`);
  EventBus.emit('user_speech', { sessionId: sid, text, timestamp: Date.now() });

  const reply = await processUserInput(chatClient, sid, text, API_OK);
  console.log(`[Chat] AI回复完成: ${sid} | 结果: "${reply.substring(0, 50)}"`);

  EventBus.emit('assistant_reply', { sessionId: sid, text: reply, timestamp: Date.now() });
  console.log(`[Chat] assistant_reply 事件已发送: ${sid}`);
}

// ── 全局事件 → 对应浏览器 ──
EventBus.on('user_speech', (d) => {
  const ws = sessions.get(d.sessionId);
  if (ws) ws.send(JSON.stringify({ type: 'user_message', text: d.text, timestamp: Date.now() }));
});
EventBus.on('assistant_reply', (d) => {
  const ws = sessions.get(d.sessionId);
  if (ws) ws.send(JSON.stringify({ type: 'assistant_message', text: d.text, timestamp: Date.now() }));
});
EventBus.on('speech_start', (d) => {
  const ws = sessions.get(d.sessionId);
  if (ws) ws.send(JSON.stringify({ type: 'speech_start', timestamp: Date.now() }));
});
EventBus.on('ai_audio', (d) => {
  const ws = sessions.get(d.sessionId);
  if (ws) ws.send(JSON.stringify({ type: 'audio_output', audio: d.audio, timestamp: Date.now() }));
});

// ── SSE ──
function sseHandler(req, res) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' });
  res.write(`data: ${JSON.stringify({ type: 'connected', message: '管理端已连接', timestamp: Date.now() })}\n\n`);
  const h = {
    user_speech: (d) => res.write(`event: user_speech\ndata: ${JSON.stringify(d)}\n\n`),
    assistant_reply: (d) => res.write(`event: assistant_reply\ndata: ${JSON.stringify(d)}\n\n`),
    frame_analyzed: (d) => res.write(`event: frame_analyzed\ndata: ${JSON.stringify(d)}\n\n`),
    session_connected: (d) => res.write(`event: session_connected\ndata: ${JSON.stringify(d)}\n\n`),
    session_disconnected: (d) => res.write(`event: session_disconnected\ndata: ${JSON.stringify(d)}\n\n`),
  };
  Object.entries(h).forEach(([e, f]) => EventBus.on(e, f));
  const hb = setInterval(() => res.write(':hb\n\n'), 30000);
  req.on('close', () => { clearInterval(hb); Object.entries(h).forEach(([e, f]) => EventBus.off(e, f)); });
}

// ── 启动 ──
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n╔══════════════════════════════════════╗`);
  console.log(`║  AI 视觉对话助手 v1.0.0              ║`);
  console.log(`║  模式: ${(API_OK ? 'full (realtime)' : 'demo').padEnd(29)}║`);
  console.log(`║  地址: http://localhost:${PORT}          ║`);
  console.log(`║  管理: http://localhost:${PORT}/admin     ║`);
  console.log(`╚══════════════════════════════════════╝\n`);
});