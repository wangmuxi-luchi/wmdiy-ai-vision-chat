import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Plays TTS audio received from the backend.
class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  AudioPlayerService() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
    });
  }

  /// Play MP3 audio bytes received from TTS.
  Future<void> playBytes(Uint8List audioBytes) async {
    try {
      // Save to temp file (audioplayers needs a source)
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(audioBytes);

      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  /// Stop current playback.
  Future<void> stop() async {
    await _player.stop();
  }

  /// Set volume (0.0 - 1.0).
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _player.dispose();
  }
}
