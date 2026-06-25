/**
 * Scene Memory — 维护当前视觉场景状态
 * 保存最近画面描述，为实时语音会话提供视觉上下文
 */

class SceneMemory {
  constructor() {
    this.description = '尚未获取画面';
    this.lastUpdate = 0;
    this.history = []; // 最近 5 条画面描述
    this.maxHistory = 5;
  }

  /**
   * 更新当前场景描述
   * @param {string} description - 画面描述
   */
  update(description) {
    if (!description) return;
    this.description = description;
    this.lastUpdate = Date.now();
    this.history.push(description);
    if (this.history.length > this.maxHistory) {
      this.history.shift();
    }
  }

  /**
   * 获取视觉上下文（注入到实时语音 session）
   * @returns {string}
   */
  getContext() {
    if (!this.description || this.description === '尚未获取画面') {
      return '尚未获取画面信息。';
    }
    // 组合当前 + 最近变化
    let ctx = `当前画面：${this.description}`;
    if (this.history.length > 1) {
      const recent = this.history.slice(-3).filter(d => d !== this.description);
      if (recent.length > 0) {
        ctx += `\n最近画面变化：${recent.join('；')}`;
      }
    }
    return ctx;
  }

  /**
   * 判断场景是否有明显变化
   * @param {string} newDescription
   * @returns {boolean}
   */
  hasSignificantChange(newDescription) {
    if (!this.description || this.description === '尚未获取画面') return true;
    // 简单比较前 30 个字符
    return newDescription.substring(0, 30) !== this.description.substring(0, 30);
  }

  /**
   * 清理
   */
  reset() {
    this.description = '尚未获取画面';
    this.lastUpdate = 0;
    this.history = [];
  }
}

// 每个会话的场景记忆
const sceneMemories = new Map();

function getSceneMemory(sessionId) {
  if (!sceneMemories.has(sessionId)) {
    sceneMemories.set(sessionId, new SceneMemory());
  }
  return sceneMemories.get(sessionId);
}

function removeSceneMemory(sessionId) {
  sceneMemories.delete(sessionId);
}

module.exports = { SceneMemory, getSceneMemory, removeSceneMemory };
