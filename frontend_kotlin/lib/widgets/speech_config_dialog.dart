import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/locator.dart';
import '../services/speech_recognition_service.dart';
import '../services/impl/asr_speech_recognition_service.dart';

class SpeechConfigDialog extends StatefulWidget {
  const SpeechConfigDialog({super.key});

  @override
  State<SpeechConfigDialog> createState() => _SpeechConfigDialogState();
}

class _SpeechConfigDialogState extends State<SpeechConfigDialog> {
  late ConfigService _configService;
  late SpeechRecognitionService _speechService;
  late SpeechConfig _config;
  late TextEditingController _appIdController;
  late TextEditingController _secretIdController;
  late TextEditingController _secretKeyController;
  late TextEditingController _regionController;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _configService = locator<ConfigService>();
    _speechService = locator<SpeechRecognitionService>();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    _config = await _configService.getSpeechConfig();
    _appIdController = TextEditingController(text: _config.appId);
    _secretIdController = TextEditingController(text: _config.secretId);
    _secretKeyController = TextEditingController(text: _config.secretKey);
    _regionController = TextEditingController(text: _config.region);
    setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    
    final newConfig = SpeechConfig(
      appId: _appIdController.text,
      secretId: _secretIdController.text,
      secretKey: _secretKeyController.text,
      region: _regionController.text.isNotEmpty ? _regionController.text : 'ap-beijing',
    );
    
    await _configService.saveSpeechConfig(newConfig);
    
    if (_speechService is ASRSpeechRecognitionService) {
      await (_speechService as ASRSpeechRecognitionService).updateConfig();
    }
    
    setState(() {
      _isSaving = false;
      _config = newConfig;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已更新并立即生效')),
      );
      Navigator.pop(context);
    }
  }

  void _clearConfig() {
    _appIdController.clear();
    _secretIdController.clear();
    _secretKeyController.clear();
    _regionController.text = 'ap-beijing';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: Center(child: CircularProgressIndicator()),
      );
    }
    
    return AlertDialog(
      title: const Text('语音转文字配置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _appIdController,
              decoration: const InputDecoration(
                labelText: 'App ID',
                hintText: '腾讯云 App ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _secretIdController,
              decoration: const InputDecoration(
                labelText: 'Secret ID',
                hintText: '腾讯云 Secret ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _secretKeyController,
              decoration: const InputDecoration(
                labelText: 'Secret Key',
                hintText: '腾讯云 Secret Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _regionController,
              decoration: const InputDecoration(
                labelText: '地域',
                hintText: '如: ap-beijing',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _config.isValid 
                ? const Text(
                    '✓ 配置已完成', 
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  )
                : const Text(
                    '提示: 填写完整配置以启用语音转文字功能', 
                    style: TextStyle(color: Colors.grey),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _clearConfig,
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: _isSaving ? null : _saveConfig,
          child: _isSaving 
              ? const CircularProgressIndicator(strokeWidth: 2)
              : const Text('保存'),
        ),
      ],
    );
  }
}