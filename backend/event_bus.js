/**
 * 事件总线 — 用于实时向管理端推送消息
 */

const EventEmitter = require('events');

class EventBus extends EventEmitter {}

// 单例
const bus = new EventBus();
bus.setMaxListeners(50); // 允许多个监听器

module.exports = bus;
