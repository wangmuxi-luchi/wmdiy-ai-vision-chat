import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'utils/logger.dart';

void forcePlayVideoElement() {
  const String tag = 'forcePlayVideo';
  int attempts = 0;
  Timer.periodic(const Duration(milliseconds: 50), (timer) {
    attempts++;
    try {
      final doc = globalContext.getProperty('document'.toJS) as JSObject?;
      if (doc == null) {
        if (attempts >= 20) timer.cancel();
        return;
      }

      final video = doc.callMethod('querySelector'.toJS, 'video'.toJS) as JSObject?;
      if (video != null) {
        video.callMethod('play'.toJS);
        Logger.d(tag, '视频元素 play() 已调用 (第$attempts次尝试)');
        timer.cancel();
      } else if (attempts >= 20) {
        Logger.d(tag, '超时未找到 video 元素');
        timer.cancel();
      }
    } catch (e) {
      Logger.d(tag, '异常: $e');
      timer.cancel();
    }
  });
}