"""
Agent orchestrator — integrates deepagents as the AI reasoning layer.
Manages conversation context and routes between vision/audio/response.
"""

import asyncio
import logging

logger = logging.getLogger(__name__)

_agent = None
_agent_init_lock = asyncio.Lock()


def _get_openai_client():
    """Lazy import to avoid circular dependency with main.py."""
    from main import state
    return state.openai_client


async def get_agent():
    """
    Lazy-initialize and return the deepagents agent.
    Falls back to None (simple fallback) in demo mode or on failure.
    """
    global _agent

    if _agent is not None:
        return _agent

    async with _agent_init_lock:
        if _agent is not None:
            return _agent

        from main import state

        # In demo mode, skip deepagents entirely
        if not state.api_key_available:
            logger.info("Demo mode: deepagents disabled, using fallback processor")
            _agent = None
            return _agent

        # Try to initialize deepagents with a timeout
        try:
            logger.info("Initializing deepagents agent...")

            def _init_agent():
                from deepagents import create_deep_agent
                return create_deep_agent(
                    model="openai:gpt-4o",
                    system_prompt="""你是 AI 视觉对话助手，运行在用户手机上。
你可以实时看到用户摄像头画面、听到用户说的话。

## 核心原则
1. 回答尽量简洁（1-3句话），适合语音播报，不要用 markdown 格式
2. 如果用户没说话但画面有变化，主动描述画面
3. 如果用户问了关于画面内容的问题，结合画面信息回答
4. 使用中文回答，除非用户用其他语言提问

## 工作方式
- 你收到的消息格式是：画面描述 + 用户语音文本
- 基于这两部分信息综合分析并回应""",
                    tools=[analyze_visual_context, get_conversation_summary],
                )

            _agent = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(None, _init_agent),
                timeout=30.0,
            )
            logger.info("deepagents agent initialized successfully")
        except asyncio.TimeoutError:
            logger.warning("deepagents init timed out after 30s, using fallback")
            _agent = None
        except Exception as e:
            logger.warning("deepagents init failed: %s, using fallback", e)
            _agent = None

        return _agent


async def _fallback_process(user_text: str, frame_description: str | None = None) -> str:
    """Simple fallback when deepagents is unavailable."""
    from main import state

    # If we have an API key, do a direct OpenAI call
    if state.api_key_available and state.openai_client:
        try:
            messages = []
            if frame_description:
                messages.append({
                    "role": "user",
                    "content": f"画面内容: {frame_description}"
                })
            messages.append({
                "role": "user",
                "content": user_text
            })

            response = await state.openai_client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{
                    "role": "system",
                    "content": "你是视觉对话助手。回答简洁（1-3句），不要用markdown，使用中文。"
                }] + messages,
                max_tokens=300,
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            logger.warning("Fallback OpenAI call failed: %s", e)

    # Last resort: echo reply in demo mode
    if frame_description:
        return f"我看到：{frame_description[:80]}... 你说：{user_text}（演示模式 — 未配置 API Key）"
    return f"你说：{user_text}（演示模式 — 请设置 OPENAI_API_KEY 使用完整功能）"


async def analyze_visual_context(session_id: str | None = None) -> str:
    """
    Tool: retrieve the latest camera frame description for the session.
    Called by deepagents when it needs visual context.
    """
    try:
        from cost_controller import frame_controller
        if session_id:
            desc = frame_controller.get_latest_description(session_id)
            if desc:
                return f"当前画面: {desc}"
        return "当前画面: 暂无画面信息（等待新帧）"
    except Exception as e:
        logger.warning("analyze_visual_context error: %s", e)
        return "当前画面: 获取失败"


async def get_conversation_summary(session_id: str | None = None) -> str:
    """
    Tool: return a summary of the recent conversation history.
    Used for context management when token budget is tight.
    """
    try:
        from cost_controller import conversation_budget
        if session_id:
            messages = conversation_budget.get_recent_context(session_id, 5)
            if messages:
                parts = [f"{m['role']}: {m['content']}" for m in messages]
                return "最近对话:\n" + "\n".join(parts)
        return "暂无对话历史"
    except Exception as e:
        logger.warning("get_conversation_summary error: %s", e)
        return "获取历史失败"


async def process_user_input(
    session_id: str,
    user_text: str,
    frame_description: str | None = None,
) -> str:
    """
    Main conversation loop:
    1. Get/init the agent
    2. Build context (visual + speech)
    3. Invoke agent with context
    4. Track token usage
    5. Return reply text
    """
    agent = await get_agent()

    # Build the combined prompt with visual + audio context
    context_parts = []
    if frame_description:
        context_parts.append(f"[画面]: {frame_description}")
    context_parts.append(f"[用户]: {user_text}")

    prompt = "\n".join(context_parts)

    logger.info("Agent input (session=%s): %.150s", session_id, prompt)

    from cost_controller import conversation_budget

    try:
        if agent is None:
            # Fallback when deepagents is unavailable
            reply = await _fallback_process(user_text, frame_description)
        else:
            # Invoke the agent using deepagents (sync call in executor)
            def _invoke():
                result = agent.invoke({"messages": [{"role": "user", "content": prompt}]})
                messages = result.get("messages", [])
                for msg in messages:
                    if msg.get("role") == "assistant" and msg.get("content"):
                        return msg["content"]
                if messages:
                    return messages[-1].get("content", "")
                return ""

            reply = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(None, _invoke),
                timeout=60.0,
            )

        if not reply:
            return "嗯，我在听。"

        # Rough token estimate for cost tracking
        estimated_input_tokens = len(prompt) // 2
        estimated_output_tokens = len(reply) // 2

        conversation_budget.add_message(session_id, "user", user_text, estimated_input_tokens)
        conversation_budget.add_message(session_id, "assistant", reply, estimated_output_tokens)

        # Trigger summarization if budget exceeded
        if agent is not None and conversation_budget.needs_summary(session_id):
            try:
                def _summarize():
                    summary_response = agent.invoke({
                        "messages": [{
                            "role": "user",
                            "content": f"请用一句话总结以上对话，保留关键信息。原始对话内容：{reply}"
                        }]
                    })
                    return summary_response.get("messages", [{}])[-1].get("content", reply)

                summary = await asyncio.wait_for(
                    asyncio.get_event_loop().run_in_executor(None, _summarize),
                    timeout=30.0,
                )
                conversation_budget.replace_with_summary(
                    session_id, summary, len(summary) // 2
                )
                logger.info("Conversation summarized for session=%s", session_id)
            except Exception as e:
                logger.warning("Summarization failed: %s", e)

        logger.info("Agent reply (session=%s): %.100s", session_id, reply)
        return reply

    except asyncio.TimeoutError:
        logger.error("Agent invocation timed out (session=%s)", session_id)
        return "抱歉，处理超时，请再试一次。"
    except Exception as e:
        logger.error("Agent invocation failed: %s", e, exc_info=True)
        return f"抱歉，处理出错: {str(e)[:100]}"
