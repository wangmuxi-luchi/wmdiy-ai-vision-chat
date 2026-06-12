import 'package:get_it/get_it.dart';
import 'speech_recognition_service.dart';
import 'text_processor_service.dart';
import 'message_receiver_service.dart';
import 'command_receiver_service.dart';
import 'camera_image_service.dart';
import 'camera_service.dart';
import 'impl/asr_speech_recognition_service.dart';
import 'impl/backend_text_processor_service.dart';
import 'impl/mock_message_receiver_service.dart';
import 'impl/mock_command_receiver_service.dart';
import 'impl/mock_camera_image_service.dart';
import 'impl/camera_service_impl.dart';
import 'impl/mock_camera_service.dart';

final GetIt locator = GetIt.instance;

void setupLocator({bool useMock = false}) {
  if (!locator.isRegistered<SpeechRecognitionService>()) {
    locator.registerLazySingleton<SpeechRecognitionService>(
      () => ASRSpeechRecognitionService(),
    );
  }
  if (!locator.isRegistered<TextProcessorService>()) {
    locator.registerLazySingleton<TextProcessorService>(
      () => BackendTextProcessorService(),
    );
  }
  if (!locator.isRegistered<MessageReceiverService>()) {
    locator.registerLazySingleton<MessageReceiverService>(
      () => MockMessageReceiverService(),
    );
  }
  if (!locator.isRegistered<CommandReceiverService>()) {
    locator.registerLazySingleton<CommandReceiverService>(
      () => MockCommandReceiverService(),
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
}

void resetLocator() {
  locator.reset();
}