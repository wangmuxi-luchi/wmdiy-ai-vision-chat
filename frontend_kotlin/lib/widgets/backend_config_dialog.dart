import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/locator.dart';
import '../services/communication_service.dart';

class BackendConfigDialog extends StatefulWidget {
  const BackendConfigDialog({super.key});

  @override
  State<BackendConfigDialog> createState() => _BackendConfigDialogState();
}

class _BackendConfigDialogState extends State<BackendConfigDialog> {
  late ConfigService _configService;
  late CommunicationService _communicationService;
  late BackendConfig _config;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _protocolController;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _configService = locator<ConfigService>();
    _communicationService = locator<CommunicationService>();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    _config = await _configService.getBackendConfig();
    _hostController = TextEditingController(text: _config.host);
    _portController = TextEditingController(text: _config.port.toString());
    _protocolController = TextEditingController(text: _config.protocol);
    setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    
    final port = int.tryParse(_portController.text) ?? 8000;
    
    final newConfig = BackendConfig(
      host: _hostController.text.isNotEmpty ? _hostController.text : 'localhost',
      port: port > 0 && port <= 65535 ? port : 8000,
      protocol: _protocolController.text.isNotEmpty ? _protocolController.text : 'ws',
    );
    
    await _configService.saveBackendConfig(newConfig);
    
    await _communicationService.updateConnection(newConfig.host, newConfig.port);
    
    setState(() => _isSaving = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已更新并立即生效')),
      );
      Navigator.pop(context);
    }
  }

  void _resetToDefault() {
    _hostController.text = 'localhost';
    _portController.text = '8000';
    _protocolController.text = 'ws';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: Center(child: CircularProgressIndicator()),
      );
    }
    
    return AlertDialog(
      title: const Text('后端服务配置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'localhost 或 IP地址',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '端口号',
                hintText: '默认: 8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _protocolController,
              decoration: const InputDecoration(
                labelText: '协议',
                hintText: 'ws 或 wss',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _config.isValid 
                ? Text(
                    '✓ 配置有效: ${_config.url}', 
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  )
                : const Text(
                    '提示: 请填写有效的服务器地址和端口', 
                    style: TextStyle(color: Colors.grey),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _resetToDefault,
          child: const Text('重置'),
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