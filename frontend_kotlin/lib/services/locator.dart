import 'package:get_it/get_it.dart';
import 'speech_recognition_service.dart';
import 'text_processor_service.dart';
import 'impl/asr_speech_recognition_service.dart';
import 'impl/backend_text_processor_service.dart';

final GetIt locator = GetIt.instance;

void setupLocator() {
  locator.registerLazySingleton<SpeechRecognitionService>(
    () => ASRSpeechRecognitionService(),
  );
  locator.registerLazySingleton<TextProcessorService>(
    () => BackendTextProcessorService(),
  );
}

void resetLocator() {
  locator.reset();
}