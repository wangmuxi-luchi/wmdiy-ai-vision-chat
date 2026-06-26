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
const { getSceneMemory, removeSceneMemory } = require('./scene_memory');
const { transcribeAudio, synthesizeSpeech } = require('./audio_processor');
const { SilenceDetector } = require('./cost_controller');

// PCM → WAV 编码（供 TTS 播放）
function pcmToWav(pcm, sampleRate) {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

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
app.use(express.static(path.join(__dirname, '..', 'frontend', 'public')));
app.get('/api/health', (_, res) => res.json({ status: 'ok', mode: API_OK ? 'full' : 'demo', timestamp: Date.now() }));
app.get('/', (_, res) => res.sendFile(path.join(__dirname, '..', 'frontend', 'public', 'index.html')));
app.get('/admin', (_, res) => res.sendFile(path.join(__dirname, '..', 'frontend', 'public', 'admin.html')));
app.get('/api/admin/stream', sseHandler);

// ── HTTP Server ──
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

// sessionId → ws 映射（用于事件转发）
const sessions = new Map();
// sessionId → rtMgr 映射（用于语音触发视觉注入）
const rtMgrs = new Map();

// 帧分析间隔控制：最低 8 秒分析一次，避免占满 API 配额
const FRAME_COOLDOWN = 8000; // 7.5 RPM，留余量给对话 API
const lastFrameTime = new Map();
const speechActive = new Map(); // 语音处理中暂停视觉注入

wss.on('connection', (ws) => {
  const sid = `s_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  sessions.set(sid, ws);

  console.log(`[WS] 连接: ${sid}`);

  ws.send(JSON.stringify({ type: 'connected', session_id: sid, mode: API_OK ? 'full' : 'demo', timestamp: Date.now() }));
  // 预热 vision API：连接时截一帧
  ws.send(JSON.stringify({ type: 'command', data: 'capture_frame' }));
  EventBus.emit('session_connected', { sessionId: sid, timestamp: Date.now() });

  // HTTP 音频管线，不需要实时 WebSocket
  let rtMgr = null;

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
    rtMgrs.delete(sid);
    lastFrameTime.delete(sid);
    speechActive.delete(sid);
    audioChunks.delete(sid);
    audioSpeaking.delete(sid);
    if (audioSilenceTimer.has(sid)) { clearTimeout(audioSilenceTimer.get(sid)); audioSilenceTimer.delete(sid); }
    audioDetectors.delete(sid);
    agentFailCount.delete(sid);
    cleanupSession(sid);
    removeSceneMemory(sid);
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
        await handleFrame(sid, msg.data, ws, rtMgr);
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
async function handleFrame(sid, b64, ws, rtMgr) {
  if (!API_OK) {
    ws.send(JSON.stringify({ type: 'frame_analyzed', description: '[Demo] 画面', timestamp: Date.now() }));
    return;
  }

  // 帧分析间隔控制：最低 8 秒一次
  const now = Date.now();
  const lastTime = lastFrameTime.get(sid) || 0;
  if (now - lastTime < FRAME_COOLDOWN) return;
  lastFrameTime.set(sid, now);

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

    // Phase 2: 更新 Scene Memory → 注入实时语音会话
    const sceneMem = getSceneMemory(sid);
    if (sceneMem.hasSignificantChange(desc) && rtMgr?.connected) {
      sceneMem.update(desc);
      rtMgr.updateVisualContext(sceneMem.getContext());
    }
  } catch (e) {
    console.error('[Frame] 分析失败:', e.message);
    // 不发送错误信息到前端，静默跳过
  }
}

// ── 实时音频（二进制 WAV → 阶跃星辰 Realtime）──
// ── HTTP 音频管线（替代不稳定的实时 WebSocket）──
const audioChunks = new Map();      // sid → Buffer[] PCM 累积
const audioSpeaking = new Map();    // sid → boolean
const audioSilenceTimer = new Map(); // sid → setTimeout
const audioDetectors = new Map();   // sid → SilenceDetector
const agentFailCount = new Map();    // sid → 连续失败次数

function getAudioDetector(sid) {
  if (!audioDetectors.has(sid)) audioDetectors.set(sid, new SilenceDetector(800));
  return audioDetectors.get(sid);
}

async function handleAudioBinary(sid, wavBuffer, rtMgr, ws) {
  const pcm = extractPCMFromWAV(wavBuffer);
  if (pcm.length === 0) return;

  const detector = getAudioDetector(sid);
  const { isSilence } = detector.detect(pcm);

  if (!isSilence) {
    // 语音：累积 PCM
    if (!audioChunks.has(sid)) {
      audioChunks.set(sid, []);
      console.log(`[Audio] 检测到语音开始: ${sid}`);
      EventBus.emit('speech_start', { sessionId: sid, timestamp: Date.now() });
    }
    audioChunks.get(sid).push(pcm);
    audioSpeaking.set(sid, true);

    // 清除静音定时器
    if (audioSilenceTimer.has(sid)) {
      clearTimeout(audioSilenceTimer.get(sid));
      audioSilenceTimer.delete(sid);
    }
  } else if (audioSpeaking.get(sid) && audioChunks.has(sid)) {
    // 静音：启动定时器，确认用户说完
    if (!audioSilenceTimer.has(sid)) {
      audioSilenceTimer.set(sid, setTimeout(() => {
        processSpeech(sid, ws);
      }, 350));
    }
  }
}

async function processSpeech(sid, ws) {
  audioSilenceTimer.delete(sid);
  audioSpeaking.set(sid, false);
  const chunks = audioChunks.get(sid);
  if (!chunks?.length) return;
  audioChunks.delete(sid);

  const pcm = Buffer.concat(chunks);
  // 至少 0.5 秒音频才送 ASR（24kHz 16bit = 24000 bytes）
  if (pcm.length < 24000) { console.log(`[HTTP-ASR] 音频太短: ${sid}, ${pcm.length} bytes，跳过`); return; }
  const wav = pcmToWav(pcm, 24000);
  console.log(`[HTTP-ASR] 处理语音: ${sid}, ${pcm.length} bytes`);

  // 1. ASR
  let userText;
  try {
    userText = await transcribeAudio(openaiClient, wav);
  } catch (asrErr) {
    console.error(`[HTTP-ASR] 识别失败:`, asrErr.message);
    return; // 静默跳过，不显示错误
  }
  if (!userText?.trim()) { console.log(`[HTTP-ASR] 识别为空: ${sid}`); return; }
  console.log(`[HTTP-ASR] 用户说: "${userText}"`);

  EventBus.emit('user_speech', { sessionId: sid, text: userText, timestamp: Date.now() });

  // 确保画面描述就绪（用 scene_memory 缓存，不依赖正在进行的帧分析）
  const sceneMem = getSceneMemory(sid);
  if (sceneMem.description && sceneMem.description !== '尚未获取画面') {
    updateFrameDescription(sid, sceneMem.description);
  }

  // 2. Agent (step-3.7-flash + 视觉上下文)
  let reply;
  try {
    reply = await processUserInput(openaiClient, sid, userText, API_OK);
  } catch (agentErr) {
    console.error(`[HTTP-ASR] Agent 失败:`, agentErr.message);
    // 连续失败 3 次才提示用户
    const fails = (agentFailCount.get(sid) || 0) + 1;
    agentFailCount.set(sid, fails);
    if (fails >= 3) {
      EventBus.emit('assistant_reply', { sessionId: sid, text: '出了点问题，请稍后再试。', timestamp: Date.now() });
      agentFailCount.set(sid, 0);
    }
    return;
  }
  console.log(`[HTTP-ASR] Agent 回复: "${reply.substring(0, 50)}"`);
  agentFailCount.set(sid, 0); // 成功时重置失败计数
  EventBus.emit('assistant_reply', { sessionId: sid, text: reply, timestamp: Date.now() });

  // 3. TTS
  try {
    const mp3 = await synthesizeSpeech(openaiClient, reply);
    ws.send(mp3);
    console.log(`[HTTP-TTS] 语音发送完成: ${sid} (${mp3.length} bytes)`);
  } catch (ttsErr) {
    console.error(`[HTTP-TTS] 失败:`, ttsErr.message);
  }
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
  speechActive.set(d.sessionId, true);
});
EventBus.on('assistant_reply', (d) => {
  speechActive.set(d.sessionId, false); // AI 回复完成，恢复视觉注入
});
EventBus.on('ai_text_delta', (d) => {
  const ws = sessions.get(d.sessionId);
  if (ws) ws.send(JSON.stringify({ type: 'ai_text_delta', delta: d.delta }));
});
EventBus.on('ai_audio', (d) => {
  const ws = sessions.get(d.sessionId);
  if (ws && ws.readyState === 1) {
    // PCM base64 → WAV buffer → 二进制帧（浏览器直接播放）
    const pcm = Buffer.from(d.audio, 'base64');
    const wav = pcmToWav(pcm, 24000);
    ws.send(wav);
  }
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