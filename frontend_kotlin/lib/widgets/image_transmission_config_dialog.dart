import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/locator.dart';
import '../utils/logger.dart';

class ImageTransmissionConfigDialog extends StatefulWidget {
  const ImageTransmissionConfigDialog({super.key});

  @override
  State<ImageTransmissionConfigDialog> createState() => _ImageTransmissionConfigDialogState();
}

class _ImageTransmissionConfigDialogState extends State<ImageTransmissionConfigDialog> {
  late ConfigService _configService;
  late ImageTransmissionConfig _config;
  final TextEditingController _intervalController = TextEditingController();
  String? _intervalError;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _configService = locator<ConfigService>();
    _loadConfig();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    _config = await _configService.getImageTransmissionConfig();
    _intervalController.text = _config.sendInterval.toString();
    setState(() => _isLoading = false);
  }

  void _validateInterval(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _intervalError = '请输入发送间隔');
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      setState(() => _intervalError = '请输入有效整数');
      return;
    }
    if (parsed < 1) {
      setState(() => _intervalError = '最小间隔为 1 秒');
      return;
    }
    setState(() {
      _intervalError = null;
      _config.sendInterval = parsed;
    });
  }

  bool _canSave() {
    if (_config.fixedIntervalEnabled) {
      return _intervalError == null && _intervalController.text.trim().isNotEmpty;
    }
    return true;
  }

  List<String> get _activeModes {
    final modes = <String>[];
    if (_config.speechTriggerEnabled) modes.add('语音触发');
    if (_config.fixedIntervalEnabled) modes.add('定时发送');
    return modes;
  }

  Future<void> _saveConfig() async {
    if (!_canSave()) return;
    setState(() => _isSaving = true);

    await _configService.saveImageTransmissionConfig(_config);
    Logger.i('ImageTransmissionConfig', '配置已保存: mode=${_config.modeLabel}, sendInterval=${_config.sendInterval}s');

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图像传输配置已更新')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: Center(child: CircularProgressIndicator()),
      );
    }

    return AlertDialog(
      title: const Text('图像传输配置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '传输模式（可多选）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('语音触发发送'),
              subtitle: const Text('接到语音信号时传输一帧图片'),
              value: _config.speechTriggerEnabled,
              onChanged: (value) {
                setState(() {
                  _config.speechTriggerEnabled = value ?? false;
                });
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('定时发送'),
              subtitle: const Text('以固定间隔持续发送图像'),
              value: _config.fixedIntervalEnabled,
              onChanged: (value) {
                setState(() {
                  _config.fixedIntervalEnabled = value ?? false;
                });
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            // 发送间隔设置（仅在定时发送勾选时显示）
            if (_config.fixedIntervalEnabled) ...[
              const SizedBox(height: 16),
              const Text(
                '发送间隔设置',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '间隔（秒）',
                        hintText: '最小 1 秒',
                        errorText: _intervalError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _validateInterval,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '每 $_intervalController.text 秒自动发送一帧图像',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            // 当前模式说明
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
                      _activeModes.isEmpty
                          ? '当前未启用任何发送模式'
                          : _activeModes.length == 1
                              ? '当前模式：${_activeModes.first}${_config.fixedIntervalEnabled ? '（每 $_intervalController.text 秒）' : ''}'
                              : '当前模式：${_activeModes.join(' + ')}（每 $_intervalController.text 秒），语音触发时会重置定时器',
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
              _config = ImageTransmissionConfig(
                speechTriggerEnabled: true,
                fixedIntervalEnabled: false,
                sendInterval: 5,
              );
              _intervalController.text = '5';
              _intervalError = null;
            });
          },
          child: const Text('重置'),
        ),
        TextButton(
          onPressed: (_isSaving || !_canSave()) ? null : _saveConfig,
          child: _isSaving
              ? const CircularProgressIndicator(strokeWidth: 2)
              : const Text('保存'),
        ),
      ],
    );
  }
}