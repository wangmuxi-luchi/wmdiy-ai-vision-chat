/**
 * AI 视觉对话助手 — 实时语音视觉对话
 */

// ==================== DOM ====================
const $ = id => document.getElementById(id);
const E = {
  permScreen: $('permScreen'), startBtn: $('startBtn'), permErr: $('permErr'),
  mainApp: $('mainApp'), camVideo: $('camVideo'), camCanvas: $('camCanvas'),
  visionBar: $('visionBar'), msgList: $('msgList'), typingDots: $('typingDots'),
  audioMeter: $('audioMeter'), meterBar: $('meterBar'), meterLabel: $('meterLabel'),
  micBtn: $('micBtn'), camBtn: $('camBtn'),
  connDot: $('connDot'), connText: $('connText'),
};

// ==================== State ====================
let ws = null, connected = false;
let cameraStream = null, audioStream = null;
let frameTimer = null;
let audioCtx = null, analyser = null, meterTimer = null;
let wavInterval = null;
let facingMode = 'user';
let micMuted = false;
let reconnectTimer = null;

// 预连接 WebSocket
connectWS();

// ==================== Startup ====================

E.startBtn.addEventListener('click', async () => {
  E.startBtn.disabled = true;
  E.startBtn.textContent = '正在请求权限...';
  E.permErr.classList.add('hidden');

  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: { ideal: facingMode } },
      audio: { sampleRate: 16000, channelCount: 1, echoCancellation: true, noiseSuppression: true },
    });

    // 分离音视频
    cameraStream = new MediaStream(stream.getVideoTracks());
    audioStream = new MediaStream(stream.getAudioTracks());

    // 初始化音频分析器
    initAudioMeter(audioStream);

    // 显示主界面
    E.permScreen.classList.add('hidden');
    E.mainApp.classList.remove('hidden');

    // 启动摄像头预览
    E.camVideo.srcObject = cameraStream;
    E.camBtn.classList.add('on');

    // WAV 录音已在 initAudioMeter 中启动
    E.meterLabel.textContent = '收音中';

    // 连接成功后开始帧捕获
    if (connected) startFrameCapture();

  } catch (err) {
    E.startBtn.disabled = false;
    E.startBtn.textContent = '重新尝试';
    const name = err.name || '';
    if (name.includes('NotAllowed')) {
      E.permErr.textContent = '需要摄像头和麦克风权限。请在浏览器设置中允许访问后重试。';
    } else if (name.includes('NotFound')) {
      E.permErr.textContent = '未检测到摄像头或麦克风，请连接设备后重试。';
    } else {
      E.permErr.textContent = `启动失败: ${err.message}`;
    }
    E.permErr.classList.remove('hidden');
  }
});

// ==================== WebSocket ====================

function connectWS() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const url = `${proto}//${location.host}/ws`;

  try {
    ws = new WebSocket(url);
    ws.binaryType = 'blob';

    ws.onopen = () => {
      connected = true;
      updateConn('on', '在线');
      if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
      if (cameraStream) startFrameCapture();
      // WAV 录制持续运行，重连后恢复发送
    };

    ws.onmessage = (ev) => {
      if (ev.data instanceof Blob || ev.data instanceof ArrayBuffer) {
        playTTS(ev.data);
        return;
      }
      try { handleMsg(JSON.parse(ev.data)); } catch { /* */ }
    };

    ws.onclose = () => {
      connected = false;
      stopFrameCapture();
      updateConn('off', '重连中...');
      reconnectTimer = setTimeout(connectWS, 2000);
    };

    ws.onerror = () => { connected = false; updateConn('off', '错误'); };
  } catch {
    reconnectTimer = setTimeout(connectWS, 3000);
  }
}

function send(obj) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
}

let pendingAiMsg = null;
let pendingUserText = null;
let ignoringOld = false; // 插话时忽略旧 AI 消息

function handleMsg(msg) {
  switch (msg.type) {
    case 'connected':
      updateConn('on', '在线');
      break;
    case 'speech_start':
      if (pendingAiMsg) {
        pendingAiMsg.remove();
        pendingAiMsg = null;
      }
      ignoringOld = true;
      captureFrame(); // VAD 检测到语音立刻截帧，与 ASR 并行
      break;
    case 'user_message':
      ignoringOld = false;
      if (pendingAiMsg) {
        pendingUserText = msg.text;
      } else {
        addMsg('user', msg.text);
        E.typingDots.classList.remove('hidden');
      }
      break;
    case 'ai_text_delta':
      if (ignoringOld) break;
      E.typingDots.classList.add('hidden');
      if (!pendingAiMsg) {
        pendingAiMsg = addMsg('ai', msg.delta);
      } else {
        pendingAiMsg.textContent += msg.delta;
        scrollChat();
      }
      break;
    case 'assistant_message':
      if (ignoringOld) break;
      E.typingDots.classList.add('hidden');
      if (pendingAiMsg) {
        pendingAiMsg.textContent = msg.text;
        pendingAiMsg = null;
      } else {
        addMsg('ai', msg.text);
      }
      if (pendingUserText) {
        addMsg('user', pendingUserText);
        pendingUserText = null;
        E.typingDots.classList.remove('hidden');
      }
      break;
    case 'frame_analyzed':
      break;
    case 'command':
      if (msg.data === 'capture_frame') captureFrame();
      break;
  }
}

function updateConn(cls, text) {
  E.connDot.className = `dot ${cls}`;
  E.connText.textContent = text;
}

// ==================== WAV 编码 ====================

function encodeWAV(samples, sampleRate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);

  function writeString(offset, str) {
    for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
  }

  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * bitsPerSample / 8;
  const blockAlign = numChannels * bitsPerSample / 8;
  const dataSize = samples.length * blockAlign;

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  writeString(36, 'data');
  view.setUint32(40, dataSize, true);

  // 写入采样数据 (float -1..1 → int16)
  let offset = 44;
  for (let i = 0; i < samples.length; i++) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
    offset += 2;
  }

  return buffer;
}

// ==================== Audio Meter + PCM Capture ====================

let pcmSamples = []; // 累积 PCM 采样
let scriptProcessor = null;
let sampleRate = 16000;

function initAudioMeter(stream) {
  try {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    sampleRate = audioCtx.sampleRate;

    const source = audioCtx.createMediaStreamSource(stream);

    // 分析器（电平表）
    analyser = audioCtx.createAnalyser();
    analyser.fftSize = 256;
    analyser.smoothingTimeConstant = 0.8;
    source.connect(analyser);

    // ScriptProcessor 捕获 PCM
    scriptProcessor = audioCtx.createScriptProcessor(4096, 1, 1);
    scriptProcessor.onaudioprocess = (e) => {
      if (micMuted) return;
      const input = e.inputBuffer.getChannelData(0);
      // 降采样到 24kHz（阶跃星辰实时语音要求）
      const ratio = sampleRate / 24000;
      for (let i = 0; i < input.length; i += ratio) {
        pcmSamples.push(input[Math.floor(i)]);
      }
    };
    source.connect(scriptProcessor);
    scriptProcessor.connect(audioCtx.destination); // 需要连接才能触发

    // 每 300ms 截取，缩短话音传输延迟
    const SILENCE_RMS = 0.002; // 静音阈值
    wavInterval = setInterval(() => {
      if (micMuted || !connected || pcmSamples.length < 1200) {
        pcmSamples = [];
        return;
      }
      const samples = pcmSamples.splice(0);

      let sumSq = 0;
      for (let i = 0; i < samples.length; i++) sumSq += samples[i] * samples[i];
      const rms = Math.sqrt(sumSq / samples.length);
      if (rms < SILENCE_RMS) return;

      const wavBuffer = encodeWAV(samples, 24000);
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(new Uint8Array(wavBuffer).buffer);
      }
    }, 300);

    const dataArray = new Uint8Array(analyser.frequencyBinCount);

    meterTimer = setInterval(() => {
      analyser.getByteFrequencyData(dataArray);
      // 计算平均音量 (0-255)
      let sum = 0;
      for (let i = 0; i < dataArray.length; i++) sum += dataArray[i];
      const avg = sum / dataArray.length;

      // 映射到百分比宽度
      const pct = Math.min(avg / 128 * 100, 100);
      E.meterBar.style.setProperty('--level', pct + '%');
      E.meterBar.style.background = `linear-gradient(to right,
        ${pct < 10 ? '#22c55e' : pct < 40 ? '#22c55e' : pct < 70 ? '#eab308' : '#ef4444'}
        ${pct}%, rgba(255,255,255,.15) ${pct}%)`;

      // 更新标签
      if (micMuted) {
        E.meterLabel.textContent = '已静音';
      } else if (pct < 3) {
        E.meterLabel.textContent = '安静';
      } else if (pct < 15) {
        E.meterLabel.textContent = '收音中';
      } else if (pct < 40) {
        E.meterLabel.textContent = '说话中';
      } else {
        E.meterLabel.textContent = '大声';
      }
    }, 80);
  } catch (err) {
    console.warn('音频分析器初始化失败:', err);
    E.meterLabel.textContent = '监听中';
  }
}

// ==================== Camera ====================

function captureFrame() {
  if (!cameraStream || !connected) return;
  try {
    const ctx = E.camCanvas.getContext('2d');
    E.camCanvas.width = 320;
    E.camCanvas.height = 240;
    ctx.drawImage(E.camVideo, 0, 0, 320, 240);
    const b64 = E.camCanvas.toDataURL('image/jpeg', 0.5).split(',')[1];
    send({ type: 'frame', data: b64 });
  } catch { /* */ }
}

function startFrameCapture() {}  // 按需截图，不定时
function stopFrameCapture() {}

async function toggleCamera() {
  if (cameraStream) {
    stopFrameCapture();
    cameraStream.getTracks().forEach(t => t.stop());
    cameraStream = null;
    E.camVideo.srcObject = null;
    E.camBtn.classList.remove('on');
    E.visionBar.classList.add('hidden');
  } else {
    try {
      cameraStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: facingMode }, width: { ideal: 640 }, height: { ideal: 480 } },
      });
      E.camVideo.srcObject = cameraStream;
      E.camBtn.classList.add('on');
      if (connected) startFrameCapture();
    } catch (err) {
      addMsg('ai', '摄像头开启失败: ' + err.message);
    }
  }
}

// ==================== Audio Mute Toggle ====================

function toggleMic() {
  micMuted = !micMuted;
  if (micMuted) {
    pcmSamples = [];
    E.micBtn.classList.add('muted');
    E.meterLabel.textContent = '已静音';
  } else {
    pcmSamples = [];
    E.micBtn.classList.remove('muted');
  }
}

// ==================== TTS ====================

let audioQueue = [];
let audioPlaying = false;

async function playTTS(blob) {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  // 恢复挂起的 AudioContext（浏览器切后台/静默会挂起）
  if (audioCtx.state === 'suspended') {
    await audioCtx.resume();
  }
  try {
    const buf = await audioCtx.decodeAudioData(await blob.arrayBuffer());
    audioQueue.push(buf);
    if (!audioPlaying) playNextInQueue();
  } catch {
    try {
      const url = URL.createObjectURL(blob);
      const a = new Audio(url); a.play();
      a.onended = () => URL.revokeObjectURL(url);
    } catch { /* */ }
  }
}

function playNextInQueue() {
  if (audioQueue.length === 0) {
    audioPlaying = false;
    return;
  }
  audioPlaying = true;
  const buf = audioQueue.shift();
  const src = audioCtx.createBufferSource();
  src.buffer = buf;
  src.connect(audioCtx.destination);
  src.onended = playNextInQueue;
  src.start();
}

// ==================== Chat UI ====================

function addMsg(role, text) {
  const div = document.createElement('div');
  div.className = `msg msg-${role === 'ai' ? 'ai' : 'user'}`;
  div.textContent = text;
  E.msgList.appendChild(div);
  while (E.msgList.children.length > 40) E.msgList.firstChild.remove();
  scrollChat();
  return div;
}

function scrollChat() {
  requestAnimationFrame(() => {
    const el = E.msgList.parentElement;
    if (el) el.scrollTop = el.scrollHeight;
  });
}

// ==================== Events ====================

E.micBtn.addEventListener('click', toggleMic);
E.camBtn.addEventListener('click', toggleCamera);

// 空格键切换静音
document.addEventListener('keydown', e => {
  if (e.key === ' ' && document.activeElement === document.body && !E.permScreen.classList.contains('hidden') === false) {
    e.preventDefault();
    toggleMic();
  }
});
