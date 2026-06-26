import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/locator.dart';

class TtsConfigDialog extends StatefulWidget {
  const TtsConfigDialog({super.key});

  @override
  State<TtsConfigDialog> createState() => _TtsConfigDialogState();
}

class _TtsConfigDialogState extends State<TtsConfigDialog> {
  late ConfigService _configService;
  late TtsConfig _config;
  late TextEditingController _rateController;
  String? _rateError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _configService = locator<ConfigService>();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    _config = await _configService.getTtsConfig();
    _rateController = TextEditingController(
      text: _config.speechRate.toStringAsFixed(1),
    );
    setState(() => _isLoading = false);
  }

  void _validateRate(String value) {
    setState(() {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        _rateError = '请输入语速';
        return;
      }
      final rate = double.tryParse(trimmed);
      if (rate == null) {
        _rateError = '请输入有效数字';
        return;
      }
      if (rate <= 0) {
        _rateError = '语速必须大于 0';
        return;
      }
      if (rate >= 10) {
        _rateError = '语速必须小于 10';
        return;
      }
      _rateError = null;
    });
  }

  bool _canSave() {
    return _rateError == null && _rateController.text.trim().isNotEmpty;
  }

  Future<void> _saveConfig() async {
    final rate = double.parse(_rateController.text.trim());
    _config.speechRate = rate;
    await _configService.saveTtsConfig(_config);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('朗读配置已保存')),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: Center(child: CircularProgressIndicator()),
      );
    }

    return AlertDialog(
      title: const Text('朗读配置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '朗读语速',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '语速',
                hintText: '0.1 ~ 9.9',
                helperText: '取值范围: 大于 0 且小于 10（默认 1.0）',
                errorText: _rateError,
                border: const OutlineInputBorder(),
                suffixText: 'x',
              ),
              onChanged: _validateRate,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前语速: ${_rateController.text}x${_rateError == null ? '' : '（无效）'}',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _rateController.text = '1.0';
              _rateError = null;
            });
          },
          child: const Text('重置'),
        ),
        TextButton(
          onPressed: _canSave() ? _saveConfig : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}