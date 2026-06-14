import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'speech_recognition_service.dart';
import 'text_processor_service.dart';
import 'message_receiver_service.dart';
import 'command_receiver_service.dart';
import 'camera_image_service.dart';
import 'camera_service.dart';
import 'communication_service.dart';
import 'config_service.dart';
import 'impl/asr_speech_recognition_service.dart';
import 'impl/web_speech_recognition_service.dart';
import 'impl/backend_text_processor_service.dart';
import 'impl/mock_message_receiver_service.dart';
import 'impl/message_receiver_service_impl.dart';
import 'impl/mock_command_receiver_service.dart';
import 'impl/command_receiver_service_impl.dart';
import 'impl/mock_camera_image_service.dart';
import 'impl/mock_camera_service.dart';
import 'impl/web_socket_communication_service.dart';
import 'impl/mock_communication_service.dart';

final GetIt locator = GetIt.instance;

void setupLocator({bool useMock = false}) {
  if (!locator.isRegistered<ConfigService>()) {
    locator.registerLazySingleton<ConfigService>(
      () => ConfigService(),
    );
  }
  
  if (!locator.isRegistered<SpeechRecognitionService>()) {
    locator.registerLazySingleton<SpeechRecognitionService>(
      () {
        // 根据平台选择不同的语音识别实现
        if (useMock) {
          return ASRSpeechRecognitionService();
        } else if (kIsWeb) {
          // Web 使用 JS SDK
          return WebSpeechRecognitionService();
        } else {
          // Android/iOS 使用腾讯云原生 SDK
          return ASRSpeechRecognitionService();
        }
      },
    );
  }
  
  if (!locator.isRegistered<TextProcessorService>()) {
    locator.registerLazySingleton<TextProcessorService>(
      () => BackendTextProcessorService(),
    );
  }
  
  if (!locator.isRegistered<MessageReceiverService>()) {
    locator.registerLazySingleton<MessageReceiverService>(
      () => useMock ? MockMessageReceiverService() : MessageReceiverServiceImpl(),
    );
  }
  
  if (!locator.isRegistered<CommandReceiverService>()) {
    locator.registerLazySingleton<CommandReceiverService>(
      () => useMock ? MockCommandReceiverService() : CommandReceiverServiceImpl(),
    );
  }
  
  if (!locator.isRegistered<CameraImageService>()) {
    locator.registerLazySingleton<CameraImageService>(
      () => MockCameraImageService(),
    );
  }
  
  if (!locator.isRegistered<CameraService>()) {
    locator.registerLazySingleton<CameraService>(
      () => useMock ? MockCameraService() : CameraServiceImpl(),
    );
  }
  
  if (!locator.isRegistered<CommunicationService>()) {
    locator.registerLazySingleton<CommunicationService>(
      () => useMock ? MockCommunicationService() : WebSocketCommunicationService(),
    );
  }
}

void resetLocator() {
  locator.reset();
}