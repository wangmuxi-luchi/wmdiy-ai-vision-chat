/**
 * 音频处理 — 阶跃星辰 ASR (语音转文字) + TTS (文字转语音)
 */

const fs = require('fs');
const path = require('path');
const { SilenceDetector } = require('./cost_controller');

const ASR_MODEL = process.env.ASR_MODEL || 'stepaudio-2.5-asr';
const TTS_MODEL = process.env.TTS_MODEL || 'step-tts-mini';
const TTS_VOICE = process.env.TTS_VOICE || 'jingdiannvsheng'; // 经典女声

const silenceDetectors = new Map();

/**
 * 语音转文字 (ASR)
 */
async function transcribeAudio(client, audioBuffer) {
  const tmpDir = path.join(__dirname, 'tmp');
  if (!fs.existsSync(tmpDir)) {
    fs.mkdirSync(tmpDir, { recursive: true });
  }

  const tmpPath = path.join(tmpDir, `audio_${Date.now()}.wav`);

  try {
    fs.writeFileSync(tmpPath, audioBuffer);
    console.log(`[ASR] 音频文件已写入: ${tmpPath} (${audioBuffer.length} bytes)`);

    // 阶跃星辰 ASR — OpenAI 兼容接口
    const response = await client.audio.transcriptions.create({
      model: ASR_MODEL,
      file: fs.createReadStream(tmpPath),
      language: 'zh',
      response_format: 'text',
    });

    console.log(`[ASR] 识别成功: "${response}"`);

    // 清理
    fs.unlinkSync(tmpPath);

    return typeof response === 'string' ? response : response.text || '';
  } catch (err) {
    console.error(`[ASR] 识别失败: ${err.message}`);
    if (err.status) console.error(`[ASR] HTTP ${err.status}: ${JSON.stringify(err.error || err.body || {})}`);
    // 保留文件用于调试
    console.error(`[ASR] 音频文件保留: ${tmpPath}`);
    throw err;
  }
}

/**
 * 文字转语音 (TTS)
 */
async function synthesizeSpeech(client, text) {
  try {
    console.log(`[TTS] 合成: "${text.substring(0, 30)}..."`);
    const response = await client.audio.speech.create({
      model: TTS_MODEL,
      voice: TTS_VOICE,
      input: text,
      response_format: 'mp3',
      speed: 1.0,
    });
    const buffer = Buffer.from(await response.arrayBuffer());
    console.log(`[TTS] 合成完成: ${buffer.length} bytes`);
    return buffer;
  } catch (err) {
    console.error(`[TTS] 合成失败: ${err.message}`);
    throw err;
  }
}

/**
 * 检测音频是否为静音
 */
function detectSilence(sessionId, base64Audio) {
  if (!silenceDetectors.has(sessionId)) {
    const threshold = parseInt(process.env.SILENCE_THRESHOLD || '500', 10);
    silenceDetectors.set(sessionId, new SilenceDetector(threshold));
  }
  const detector = silenceDetectors.get(sessionId);
  try {
    return detector.detectFromBase64(base64Audio);
  } catch {
    // WebM 格式无法做 PCM RMS 检测，默认非静音
    return { isSilence: false, rms: -1 };
  }
}

/**
 * 完整音频处理管道
 */
async function processAudioChunk(client, sessionId, base64Audio, apiAvailable, onText) {
  console.log(`[Audio] 收到音频块: session=${sessionId}, size=${base64Audio.length} chars`);

  // 静音检测 (对 WebM 不准确，仅做参考)
  const { isSilence, rms } = detectSilence(sessionId, base64Audio);
  console.log(`[Audio] 静音检测: isSilence=${isSilence}, rms=${rms}`);

  if (isSilence) {
    console.log('[Audio] 静音段，跳过');
    return { userText: '', aiText: '', ttsBuffer: null, skipped: true };
  }

  // Demo 模式
  if (!apiAvailable) {
    console.log('[Audio] 演示模式，无 ASR');
    const userText = '[演示模式] 语音输入';
    return { userText, aiText: null, ttsBuffer: null, needsAgentResponse: true };
  }

  // 解码
  const audioBuffer = Buffer.from(base64Audio, 'base64');
  console.log(`[Audio] 解码后: ${audioBuffer.length} bytes`);

  // ASR
  let userText;
  try {
    userText = await transcribeAudio(client, audioBuffer);
  } catch (err) {
    console.error(`[Audio] STT 失败，丢弃此段`);
    return { userText: '', aiText: '', ttsBuffer: null, skipped: true };
  }

  if (!userText || userText.trim().length === 0) {
    console.log('[Audio] 识别结果为空');
    return { userText: '', aiText: '', ttsBuffer: null, skipped: true };
  }

  if (onText) onText(userText);
  return { userText, aiText: null, ttsBuffer: null, needsAgentResponse: true };
}

function cleanupSession(sessionId) {
  silenceDetectors.delete(sessionId);
}

module.exports = { transcribeAudio, synthesizeSpeech, detectSilence, processAudioChunk, cleanupSession };
