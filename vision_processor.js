/**
 * 视觉处理 — 帧压缩 + 阶跃星辰 Vision API
 */

const sharp = require('sharp');
const { FrameRateController } = require('./cost_controller');

// 配置
const FRAME_RESIZE = parseInt(process.env.FRAME_RESIZE || '512', 10);
const JPEG_QUALITY = parseInt(process.env.JPEG_QUALITY || '70', 10);
const VISION_MODEL = process.env.VISION_MODEL || 'step-3.7-flash';

// 每个会话的帧率控制器
const frameControllers = new Map();

/**
 * 缩放并压缩图片
 * @param {string} base64Jpeg - 原始 base64 JPEG
 * @param {number} maxSize - 最大边长
 * @returns {Promise<string>} 压缩后的 base64 JPEG
 */
async function resizeImage(base64Jpeg, maxSize = FRAME_RESIZE) {
  try {
    const buffer = Buffer.from(base64Jpeg, 'base64');
    const resized = await sharp(buffer)
      .resize(maxSize, maxSize, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: JPEG_QUALITY })
      .toBuffer();
    return resized.toString('base64');
  } catch (err) {
    console.warn('[Vision] 图片缩放失败，使用原图:', err.message);
    return base64Jpeg;
  }
}

/**
 * 调用阶跃星辰 Vision API 分析画面
 * @param {object} client - OpenAI 客户端
 * @param {string} base64Jpeg - 压缩后的 base64 JPEG
 * @param {string} previousDescription - 上一帧的描述（用于上下文）
 * @returns {Promise<string>} 画面描述
 */
async function analyzeFrame(client, base64Jpeg, previousDescription = null) {
  const imageUrl = `data:image/jpeg;base64,${base64Jpeg}`;

  const messages = [
    {
      role: 'system',
      content: `你是一个视觉助手。请简洁地描述你从摄像头画面中看到的内容。
要求：
- 用中文回复，1-2句话
- 描述人物、动作、场景、物品
- 如果与上一帧相比没有明显变化，回复"画面无明显变化"
- 不要描述不存在的细节`,
    },
    {
      role: 'user',
      content: [
        { type: 'image_url', image_url: { url: imageUrl, detail: 'low' } },
        {
          type: 'text',
          text: previousDescription
            ? `上一帧的画面描述：${previousDescription}\n\n当前画面有什么变化？请描述。`
            : '请描述摄像头当前看到的画面。',
        },
      ],
    },
  ];

  const response = await client.chat.completions.create({
    model: VISION_MODEL,
    messages,
    max_tokens: 150,
    temperature: 0.7,
  });

  const description = response.choices[0]?.message?.content || '无法分析画面';
  return description;
}

/**
 * 处理视频帧（完整管道）
 * @param {object} client - OpenAI 客户端
 * @param {string} sessionId - 会话 ID
 * @param {string} base64Jpeg - 原始帧 base64
 * @param {boolean} apiAvailable - API 是否可用
 * @returns {Promise<{ description: string, processed: boolean }>}
 */
async function processFrame(client, sessionId, base64Jpeg, apiAvailable) {
  // 帧率控制
  if (!frameControllers.has(sessionId)) {
    frameControllers.set(
      sessionId,
      new FrameRateController(
        parseFloat(process.env.MAX_FPS || '1.0'),
        parseFloat(process.env.MIN_FPS || '0.2')
      )
    );
  }

  const frameCtrl = frameControllers.get(sessionId);
  const frameHash = FrameRateController.hashFrame(base64Jpeg);
  const { shouldProcess } = frameCtrl.shouldProcessFrame(frameHash);

  if (!shouldProcess) {
    return { description: null, processed: false };
  }

  // Demo 模式：mock 回复
  if (!apiAvailable) {
    const mockDescriptions = [
      '我看到一个人正坐在电脑前，专注地看着屏幕。',
      '画面中的人似乎在工作，周围光线明亮。',
      '一个人正在室内环境中，看起来在思考什么。',
    ];
    return {
      description: mockDescriptions[Math.floor(Math.random() * mockDescriptions.length)],
      processed: true,
    };
  }

  // 压缩图片
  const compressed = await resizeImage(base64Jpeg);

  // 获取上一帧描述（从帧控制器中获取上下文）
  const frameState = frameControllers.get(sessionId);
  const previousDesc = frameState?.lastDescription || null;

  // 调用 Vision API
  const description = await analyzeFrame(client, compressed, previousDesc);

  // 保存描述
  if (frameState) {
    frameState.lastDescription = description;
  }

  return { description, processed: true };
}

/**
 * 清理会话资源
 * @param {string} sessionId
 */
function cleanupSession(sessionId) {
  frameControllers.delete(sessionId);
}

module.exports = {
  processFrame,
  analyzeFrame,
  resizeImage,
  cleanupSession,
};
