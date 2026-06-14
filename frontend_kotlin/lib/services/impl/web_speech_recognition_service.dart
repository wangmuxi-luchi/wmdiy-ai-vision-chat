// 条件导入：Web平台使用web实现，其他平台使用stub
export 'web_speech_recognition_service_stub.dart'
    if (dart.library.js) 'web_speech_recognition_service_web.dart';