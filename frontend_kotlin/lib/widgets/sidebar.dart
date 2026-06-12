import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/locator.dart';
import 'speech_config_dialog.dart';
import 'backend_config_dialog.dart';

class Sidebar extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onToggle;

  const Sidebar({
    super.key,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  late ConfigService _configService;
  bool _isSpeechConfigured = false;
  bool _isBackendConfigured = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _configService = locator<ConfigService>();
    _checkConfigs();
  }

  Future<void> _checkConfigs() async {
    final speechConfig = await _configService.getSpeechConfig();
    final backendConfig = await _configService.getBackendConfig();
    setState(() {
      _isSpeechConfigured = speechConfig.isValid;
      _isBackendConfigured = backendConfig.isValid && 
          backendConfig.host != 'localhost';
      _isLoading = false;
    });
  }

  Future<void> _openSpeechConfig() async {
    await showDialog(
      context: context,
      builder: (context) => const SpeechConfigDialog(),
    );
    await _checkConfigs();
  }

  Future<void> _openBackendConfig() async {
    await showDialog(
      context: context,
      builder: (context) => const BackendConfigDialog(),
    );
    await _checkConfigs();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: widget.isOpen ? 240 : 60,
      color: Colors.grey[800],
      child: Column(
        children: [
          // 头部
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    widget.isOpen ? Icons.arrow_left : Icons.arrow_right,
                    color: Colors.white,
                  ),
                  onPressed: widget.onToggle,
                ),
                if (widget.isOpen)
                  const Expanded(
                    child: Text(
                      '设置',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: Colors.grey[600]),
          // 按钮列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                _buildSidebarItem(
                  icon: Icons.mic,
                  label: '语音转文字配置',
                  hasBadge: !_isSpeechConfigured,
                  onTap: _openSpeechConfig,
                ),
                _buildSidebarItem(
                  icon: Icons.cloud,
                  label: '后端服务配置',
                  hasBadge: !_isBackendConfigured,
                  onTap: _openBackendConfig,
                ),
                _buildSidebarItem(
                  icon: Icons.settings,
                  label: '系统设置',
                  onTap: () {
                    if (widget.isOpen) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('系统设置功能开发中')),
                      );
                    }
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.help,
                  label: '帮助',
                  onTap: () {
                    if (widget.isOpen) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('帮助文档开发中')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    bool hasBadge = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            Stack(
              children: [
                Icon(icon, color: Colors.white, size: 24),
                if (hasBadge)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.isOpen)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}