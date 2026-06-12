import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Unified permission management for camera and microphone.
class PermissionService {
  /// Request both camera and microphone permissions.
  /// Returns true if both are granted.
  Future<bool> requestAll() async {
    final camera = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    return camera.isGranted && mic.isGranted;
  }

  /// Request camera permission only.
  Future<bool> requestCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Request microphone permission only.
  Future<bool> requestMicrophone() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if camera permission is granted.
  Future<bool> hasCamera() async {
    return await Permission.camera.isGranted;
  }

  /// Check if microphone permission is granted.
  Future<bool> hasMicrophone() async {
    return await Permission.microphone.isGranted;
  }

  /// Open app settings (called when permission is permanently denied).
  Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Check if camera permission is permanently denied.
  Future<bool> isCameraPermanentlyDenied() async {
    return await Permission.camera.isPermanentlyDenied;
  }

  /// Check if microphone permission is permanently denied.
  Future<bool> isMicrophonePermanentlyDenied() async {
    return await Permission.microphone.isPermanentlyDenied;
  }
}
