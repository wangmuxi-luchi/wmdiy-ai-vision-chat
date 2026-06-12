/**
 * 成本控制层 — 帧率控制 / 静音检测 / Token 预算
 */

class FrameRateController {
  constructor(maxFps = 1.0, minFps = 0.2) {
    this.maxFps = maxFps;
    this.minFps = minFps;
    this.currentFps = maxFps;
    this.lastFrameHash = null;
    this.staticCount = 0;
    this.lastFrameTime = 0;
    this.staticThreshold = 3; // 连续3次无变化后降频
  }

  /**
   * 判断是否应该处理当前帧
   * @param {string} frameHash - 帧内容的简单哈希
   * @returns {{ shouldProcess: boolean, fps: number }}
   */
  shouldProcessFrame(frameHash) {
    const now = Date.now();
    const minInterval = 1000 / this.currentFps;

    if (now - this.lastFrameTime < minInterval) {
      return { shouldProcess: false, fps: this.currentFps };
    }

    // 检测画面是否静止
    if (frameHash === this.lastFrameHash) {
      this.staticCount++;
      if (this.staticCount >= this.staticThreshold && this.currentFps > this.minFps) {
        this.currentFps = this.minFps;
        console.log(`[FrameRate] 场景静止，降频至 ${this.currentFps} fps`);
      }
    } else {
      this.staticCount = 0;
      if (this.currentFps < this.maxFps) {
        this.currentFps = this.maxFps;
        console.log(`[FrameRate] 检测到变化，恢复 ${this.currentFps} fps`);
      }
    }

    this.lastFrameHash = frameHash;
    this.lastFrameTime = now;
    return { shouldProcess: true, fps: this.currentFps };
  }

  /**
   * 简单的帧哈希（采样前 N 个字符）
   */
  static hashFrame(base64Data) {
    // 取 base64 中间段的字符作为简易哈希
    const len = base64Data.length;
    const samples = [
      base64Data.substring(0, 50),
      base64Data.substring(Math.floor(len / 3), Math.floor(len / 3) + 50),
      base64Data.substring(Math.floor(len * 2 / 3), Math.floor(len * 2 / 3) + 50),
      base64Data.substring(len - 50),
    ];
    return samples.join('');
  }
}

class SilenceDetector {
  constructor(threshold = 500) {
    this.threshold = threshold;
  }

  /**
   * 检测 PCM 16bit 音频是否为静音
   * @param {Buffer} pcmBuffer - PCM 16bit 单声道音频
   * @returns {{ isSilence: boolean, rms: number }}
   */
  detect(pcmBuffer) {
    // 计算 RMS (Root Mean Square)
    const samples = new Int16Array(pcmBuffer.buffer, pcmBuffer.byteOffset, pcmBuffer.length / 2);
    let sum = 0;
    for (let i = 0; i < samples.length; i++) {
      sum += samples[i] * samples[i];
    }
    const rms = Math.sqrt(sum / samples.length);
    return {
      isSilence: rms < this.threshold,
      rms: Math.round(rms),
    };
  }

  /**
   * 从 base64 编码的音频检测静音
   * @param {string} base64Audio - base64 编码的 PCM 音频
   */
  detectFromBase64(base64Audio) {
    const buffer = Buffer.from(base64Audio, 'base64');
    return this.detect(buffer);
  }
}

class ConversationBudget {
  constructor(maxTokens = 4096) {
    this.maxTokens = maxTokens;
    this.totalTokens = 0;
    this.messageCount = 0;
  }

  /**
   * 记录 Token 消耗
   * @param {number} tokens
   */
  addTokens(tokens) {
    this.totalTokens += tokens;
    this.messageCount++;
  }

  /**
   * 检查是否超出预算
   * @returns {boolean}
   */
  isOverBudget() {
    return this.totalTokens >= this.maxTokens;
  }

  /**
   * 获取预算使用比例
   * @returns {number} 0-1
   */
  usageRatio() {
    return Math.min(this.totalTokens / this.maxTokens, 1.0);
  }

  /**
   * 是否需要触发摘要（超过80%预算）
   * @returns {boolean}
   */
  needsSummarization() {
    return this.totalTokens >= this.maxTokens * 0.8;
  }

  /**
   * 重置预算
   */
  reset() {
    this.totalTokens = 0;
    this.messageCount = 0;
  }

  /**
   * 估算文本 Token 数（粗略：1 token ≈ 0.5 中文字，≈ 0.75 英文字）
   * @param {string} text
   * @returns {number}
   */
  static estimateTokens(text) {
    if (!text) return 0;
    // 中文字符约 0.5 token/字，英文约 0.25 token/字
    const chineseChars = (text.match(/[\u4e00-\u9fff]/g) || []).length;
    const otherChars = text.length - chineseChars;
    return Math.ceil(chineseChars * 0.5 + otherChars * 0.25);
  }
}

module.exports = {
  FrameRateController,
  SilenceDetector,
  ConversationBudget,
};
