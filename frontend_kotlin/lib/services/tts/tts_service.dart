abstract class TtsService {
  Future<void> speak(String text, {String language = 'zh-CN', double rate = 1.0});
  Future<void> stop();
  Future<void> pause();
  Future<void> resume();
  Future<bool> isLanguageAvailable(String language);
  Stream<dynamic> get onComplete;
  void dispose();
}