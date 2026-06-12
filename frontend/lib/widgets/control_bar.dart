import 'package:flutter/material.dart';

/// Bottom control bar with camera/mic toggle and start/stop.
class ControlBar extends StatelessWidget {
  final bool isCameraOn;
  final bool isMicOn;
  final bool isConversationActive;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleConversation;
  final VoidCallback onSwitchCamera;

  const ControlBar({
    super.key,
    required this.isCameraOn,
    required this.isMicOn,
    required this.isConversationActive,
    required this.onToggleCamera,
    required this.onToggleMic,
    required this.onToggleConversation,
    required this.onSwitchCamera,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Camera toggle
            _IconButton(
              icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
              label: '摄像头',
              color: isCameraOn ? Colors.green : Colors.grey,
              onPressed: onToggleCamera,
            ),
            // Switch camera
            _IconButton(
              icon: Icons.flip_camera_android,
              label: '翻转',
              color: theme.colorScheme.onSurface,
              onPressed: onSwitchCamera,
            ),
            // Start/Stop conversation
            GestureDetector(
              onTap: onToggleConversation,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConversationActive ? Colors.red : Colors.green,
                  boxShadow: [
                    BoxShadow(
                      color: (isConversationActive ? Colors.red : Colors.green)
                          .withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  isConversationActive ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            // Mic toggle
            _IconButton(
              icon: isMicOn ? Icons.mic : Icons.mic_off,
              label: '麦克风',
              color: isMicOn ? Colors.green : Colors.grey,
              onPressed: onToggleMic,
            ),
            // Spacer for symmetry
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _IconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: color),
          onPressed: onPressed,
        ),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}
