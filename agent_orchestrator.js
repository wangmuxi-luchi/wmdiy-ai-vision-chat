/**
 * Agent 编排 — 多模态上下文融合 + 对话管理
 */

const { ConversationBudget } = require('./cost_controller');

// 配置
const CHAT_MODEL = process.env.CHAT_MODEL || 'step-3.7-flash';
const MAX_TOKENS = parseInt(process.env.MAX_TOKENS || '4096', 10);

// 每个会话的对话历史和预算
const sessions = new Map();

/**
 * 系统提示词
 */
const SYSTEM_PROMPT = `你是一个 AI 视觉对话助手。你能够通过摄像头看到用户，通过麦克风听到用户说话。
请基于画面内容和用户的语音输入，给出自然、有帮助的回应。

要求：
- 用中文回复，口语化、自然，像朋友聊天一样
- 回复长度适中（2-4句话），不要长篇大论
- 如果画面中有值得注意的事物，可以主动提及
- 保持友好、积极的语气
- 如果用户问问题，直接回答
- 可以适当使用语气词让对话更自然`;

/**
 * 获取或创建会话
 * @param {string} sessionId
 * @returns {{ history: Array, budget: ConversationBudget }}
 */
function getSession(sessionId) {
  if (!sessions.has(sessionId)) {
    sessions.set(sessionId, {
      history: [{ role: 'system', content: SYSTEM_PROMPT }],
      budget: new ConversationBudget(MAX_TOKENS),
      frameDescription: '尚未获取画面',
    });
  }
  return sessions.get(sessionId);
}

/**
 * 更新当前帧描述
 * @param {string} sessionId
 * @param {string} description
 */
function updateFrameDescription(sessionId, description) {
  const session = getSession(sessionId);
  session.frameDescription = description;
}

/**
 * 对话推理 — 融合画面 + 语音
 * @param {object} client - OpenAI 客户端
 * @param {string} sessionId - 会话 ID
 * @param {string} userText - 用户说的话
 * @param {boolean} apiAvailable - API 是否可用
 * @returns {Promise<string>} AI 回复文本
 */
async function processUserInput(client, sessionId, userText, apiAvailable) {
  const session = getSession(sessionId);
  const { history, budget, frameDescription } = session;

  // Token 预算检查：超限时自动摘要
  if (budget.needsSummarization()) {
    await summarizeHistory(client, sessionId, apiAvailable);
  }

  // Demo 模式：mock 回复
  if (!apiAvailable) {
    const mockReplies = [
      `我看到了画面。${frameDescription}你想聊些什么呢？`,
      '你好！我在这里听着呢。虽然现在是演示模式，但我们可以继续对话。',
      '这是一个有趣的观察。配置好 API Key 后，我能给你更智能的回复。',
    ];
    const reply = mockReplies[Math.floor(Math.random() * mockReplies.length)];
    budget.addTokens(ConversationBudget.estimateTokens(reply));
    history.push({ role: 'assistant', content: reply });
    return reply;
  }

  // 构建用户消息（融合画面描述 + 语音文本）
  const userMessage = frameDescription && frameDescription !== '尚未获取画面'
    ? `[当前画面] ${frameDescription}\n[用户说] ${userText}`
    : `[用户说] ${userText}`;

  history.push({ role: 'user', content: userMessage });

  try {
    const response = await client.chat.completions.create({
      model: CHAT_MODEL,
      messages: history,
      max_tokens: 500,
      temperature: 0.8,
    });

    const reply = response.choices[0]?.message?.content || '抱歉，我没有理解你说的话。';

    // 记录 Token 消耗
    if (response.usage) {
      budget.addTokens(response.usage.total_tokens);
    } else {
      budget.addTokens(ConversationBudget.estimateTokens(userMessage + reply));
    }

    // 保持对话历史
    history.push({ role: 'assistant', content: reply });

    // 控制历史长度（保留最近 20 条消息 + system prompt）
    if (history.length > 21) {
      // 保留 system prompt + 最近 20 条
      const systemMsg = history[0];
      session.history = [systemMsg, ...history.slice(-20)];
    }

    return reply;
  } catch (err) {
    console.error('[Agent] 推理失败:', err.message);
    const fallbackReply = '抱歉，我暂时无法处理你的请求，请稍后再试。';
    history.push({ role: 'assistant', content: fallbackReply });
    return fallbackReply;
  }
}

/**
 * 纯文本对话（无画面上下文）
 * @param {object} client - OpenAI 客户端
 * @param {string} sessionId
 * @param {string} userText
 * @param {boolean} apiAvailable
 * @returns {Promise<string>}
 */
async function chatText(client, sessionId, userText, apiAvailable) {
  return processUserInput(client, sessionId, userText, apiAvailable);
}

/**
 * 摘要对话历史（Token 预算超限时）
 * @param {object} client
 * @param {string} sessionId
 * @param {boolean} apiAvailable
 */
async function summarizeHistory(client, sessionId, apiAvailable) {
  const session = getSession(sessionId);
  const { history, budget } = session;

  if (history.length <= 3 || !apiAvailable) {
    // 简单截断：保留 system prompt + 最近 6 条
    session.history = [history[0], ...history.slice(-6)];
    budget.reset();
    // 估算重置后的 tokens
    const remaining = history[0].content + session.history.slice(1).map(m => m.content).join('');
    budget.addTokens(ConversationBudget.estimateTokens(remaining));
    return;
  }

  try {
    const historyCopy = history.slice(1); // 去掉 system prompt
    const summaryResponse = await client.chat.completions.create({
      model: CHAT_MODEL,
      messages: [
        {
          role: 'system',
          content: '请用1-2句话总结以下对话的核心内容，保留关键信息。',
        },
        {
          role: 'user',
          content: historyCopy.map(m => `[${m.role}]: ${m.content}`).join('\n'),
        },
      ],
      max_tokens: 200,
      temperature: 0.3,
    });

    const summary = summaryResponse.choices[0]?.message?.content || '对话历史已压缩。';

    // 重建历史：system prompt + 摘要 + 最近 4 条
    session.history = [
      history[0],
      { role: 'system', content: `[对话摘要] ${summary}` },
      ...history.slice(-4),
    ];
    budget.reset();
    const totalText = session.history.map(m => m.content).join('');
    budget.addTokens(ConversationBudget.estimateTokens(totalText));

    console.log(`[Agent] 对话已压缩，摘要: ${summary.substring(0, 80)}...`);
  } catch (err) {
    console.warn('[Agent] 摘要失败，使用截断:', err.message);
    session.history = [history[0], ...history.slice(-6)];
    budget.reset();
  }
}

/**
 * 清理会话
 * @param {string} sessionId
 */
function cleanupSession(sessionId) {
  sessions.delete(sessionId);
}

module.exports = {
  getSession,
  updateFrameDescription,
  processUserInput,
  chatText,
  summarizeHistory,
  cleanupSession,
};
