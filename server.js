/**
 * AI 视觉对话助手 — 服务入口
 */

require('dotenv').config();

const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const OpenAI = require('openai');
const path = require('path');
const sharp = require('sharp');
const EventBus = require('./event_bus');
const { getRealtimeSession, removeRealtimeSession, extractPCMFromWAV } = require('./realtime_handler');

const PORT = parseInt(process.env.PORT || '8000', 10);
const STEPFUN_API_KEY = process.env.STEPFUN_API_KEY || '';
const STEPFUN_BASE_URL = process.env.STEPFUN_BASE_URL || 'https://api.stepfun.com/v1';
const API_OK = !!(STEPFUN_API_KEY && STEPFUN_API_KEY !== 'your_api_key_here' && STEPFUN_API_KEY.length > 10);

let openaiClient = null;
if (API_OK) {
  openaiClient = new OpenAI({ apiKey: STEPFUN_API_KEY, baseURL: STEPFUN_BASE_URL });
  console.log('[Init] 阶跃星辰 API 就绪');
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
      .catch(e => console.error(`[Realtime] 失败: ${sid}`, e.message));
  }

  ws.on('message', async (raw) => {
    let msg;
    try {
      const str = Buffer.isBuffer(raw) ? raw.toString() : String(raw);
      msg = JSON.parse(str);
    } catch { return; }

    try {
      switch (msg.type) {
        case 'ping':
          ws.send(JSON.stringify({ type: 'pong' }));
          break;
        case 'frame':
          await handleFrame(sid, msg.data, ws);
          break;
        case 'audio':
          handleAudio(sid, msg.data, rtMgr, ws);
          break;
        case 'test_chat':
          await handleChat(sid, msg.data, ws);
          break;
      }
    } catch (e) { console.error(`[WS] 错误:`, e.message); }
  });

  ws.on('close', () => {
    sessions.delete(sid);
    if (rtMgr) { rtMgr.disconnect(); removeRealtimeSession(sid); }
    EventBus.emit('session_disconnected', { sessionId: sid, timestamp: Date.now() });
    console.log(`[WS] 断开: ${sid}`);
  });
});

// ── 帧分析 ──
async function handleFrame(sid, b64, ws) {
  if (!API_OK) {
    ws.send(JSON.stringify({ type: 'frame_analyzed', description: '[Demo] 画面', timestamp: Date.now() }));
    return;
  }
  try {
    const buf = Buffer.from(b64, 'base64');
    const resized = await sharp(buf).resize(512, 512, { fit: 'inside' }).jpeg({ quality: 70 }).toBuffer();
    const r = await openaiClient.chat.completions.create({
      model: 'step-3.7-flash',
      messages: [{ role: 'user', content: [{ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${resized.toString('base64')}`, detail: 'low' } }, { type: 'text', text: '用中文一句话描述摄像头画面。' }] }],
      max_tokens: 100,
    });
    const desc = r.choices[0]?.message?.content || '无法分析';
    ws.send(JSON.stringify({ type: 'frame_analyzed', description: desc, timestamp: Date.now() }));
    EventBus.emit('frame_analyzed', { sessionId: sid, description: desc, timestamp: Date.now() });
  } catch (e) { console.error('[Frame]', e.message); }
}

// ── 实时音频 → 阶跃星辰 Realtime ──
function handleAudio(sid, b64, rtMgr, ws) {
  if (!rtMgr?.connected) return;
  try {
    const wav = Buffer.from(b64, 'base64');
    const pcm = extractPCMFromWAV(wav);
    if (pcm.length > 0) rtMgr.inputAudio(pcm);
  } catch (e) { console.error('[Audio]', e.message); }
}

// ── 文字聊天 ──
async function handleChat(sid, text, ws) {
  if (!text?.trim()) return;
  EventBus.emit('user_speech', { sessionId: sid, text, timestamp: Date.now() });

  let reply;
  if (!API_OK) {
    reply = '[演示模式] 请配置 STEPFUN_API_KEY';
  } else {
    try {
      const r = await openaiClient.chat.completions.create({
        model: 'step-3.7-flash',
        messages: [{ role: 'system', content: '你是AI视觉对话助手，用中文简洁回应，2-3句话。' }, { role: 'user', content: text }],
        max_tokens: 300,
      });
      reply = r.choices[0]?.message?.content || '抱歉，请再说一次。';
    } catch (e) {
      console.error('[Chat]', e.message);
      reply = '抱歉，暂时无法回应。';
    }
  }
  EventBus.emit('assistant_reply', { sessionId: sid, text: reply, timestamp: Date.now() });
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
