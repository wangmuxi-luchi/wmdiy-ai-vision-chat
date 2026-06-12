import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/locator.dart';
import 'services/speech_recognition_service.dart';
import 'services/text_processor_service.dart';

void main() async {
  await dotenv.load();
  setupLocator();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late SpeechRecognitionService _speechService;
  late TextProcessorService _textProcessorService;
  String _result = "";
  bool _isRecording = false;
  List<String> _sentences = [];

  @override
  void initState() {
    super.initState();
    _speechService = locator<SpeechRecognitionService>();
    _textProcessorService = locator<TextProcessorService>();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _result = "";
      _sentences = [];
    });

    try {
      Stream<String> asrStream = _speechService.startListening();
      
      asrStream.listen(
        (text) {
          if (mounted) {
            setState(() {
              _result = text;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _result = "错误: $e";
              _isRecording = false;
            });
          }
        },
        onDone: () {
          if (mounted && _isRecording) {
            setState(() {
              _isRecording = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = "错误: $e";
          _isRecording = false;
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _speechService.stopListening();
      if (_result.isNotEmpty) {
        String processed = await _textProcessorService.processText(_result);
        debugPrint("发送到后端: $processed");
      }
    } catch (e) {
      debugPrint("Error stopping recording: $e");
    } finally {
      setState(() {
        _isRecording = false;
      });
    }
  }

  @override
  void dispose() {
    _speechService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('实时语音识别')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.topLeft,
                  child: SingleChildScrollView(
                    child: Text(
                      _result.isEmpty ? '点击下方按钮开始录音识别' : _result,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  fixedSize: const Size(200, 60),
                  backgroundColor: _isRecording ? Colors.red : Colors.blue,
                ),
                onPressed: _toggleRecording,
                child: Text(
                  _isRecording ? '停止识别' : '开始识别',
                  style: const TextStyle(fontSize: 20, color: Colors.white),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}