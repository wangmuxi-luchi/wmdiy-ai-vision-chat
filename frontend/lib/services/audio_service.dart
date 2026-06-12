import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Records audio from the microphone and sends chunks via callback.
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<RecordState>? _stateSub;
  StreamSubscription<Amplitude>? _amplitudeSub;
  bool _isRecording = false;
  bool _isPaused = false;
  Timer? _chunkTimer;
  List<int> _currentChunk = [];

  // Callback when an audio chunk is ready (Base64 encoded)
  void Function(String base64Audio)? onAudioChunk;
  void Function(double amplitude)? onAmplitude;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;

  /// Check and request microphone permission.
  Future<bool> requestPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording audio in streaming mode.
  Future<void> startRecording({int chunkDurationMs = 3000}) async {
    if (_isRecording) return;

    try {
      _currentChunk = [];

      // Start streaming PCM 16-bit audio
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: 16000,
        ),
      );

      _isRecording = true;

      // Collect audio data into chunks
      _chunkTimer = Timer.periodic(Duration(milliseconds: chunkDurationMs), (_) {
        if (_currentChunk.isNotEmpty) {
          final chunk = Uint8List.fromList(_currentChunk);
          _currentChunk = [];
          final base64 = base64Encode(chunk);
          onAudioChunk?.call(base64);
        }
      });

      // Listen to the audio stream
      stream.listen(
        (data) {
          _currentChunk.addAll(data);
        },
        onError: (error) {
          debugPrint('Audio stream error: $error');
        },
        onDone: () {
          debugPrint('Audio stream ended');
        },
      );
    } catch (e) {
      debugPrint('Recording start error: $e');
      _isRecording = false;
    }
  }

  /// Pause/resume recording.
  Future<void> pause() async {
    if (!_isRecording) return;
    await _recorder.pause();
    _isPaused = true;
  }

  Future<void> resume() async {
    if (!_isRecording) return;
    await _recorder.resume();
    _isPaused = false;
  }

  /// Stop recording and flush the last chunk.
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _chunkTimer?.cancel();

    // Flush remaining data
    if (_currentChunk.isNotEmpty) {
      final chunk = Uint8List.fromList(_currentChunk);
      final base64 = base64Encode(chunk);
      onAudioChunk?.call(base64);
    }
    _currentChunk = [];

    await _recorder.stop();
    _isRecording = false;
    _isPaused = false;
  }

  /// Get current amplitude (for visualization/silence detection).
  Future<double> getAmplitude() async {
    try {
      final amplitude = await _recorder.getAmplitude();
      return amplitude.current;
    } catch (_) {
      return 0.0;
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stopRecording();
    _recorder.dispose();
  }
}
