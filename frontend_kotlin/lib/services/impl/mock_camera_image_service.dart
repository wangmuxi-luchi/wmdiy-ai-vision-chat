import '../camera_image_service.dart';

class MockCameraImageService implements CameraImageService {
  @override
  Future<String> analyzeImage(String imageData) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return '图像分析结果：画面中有一个人正在说话，背景是室内环境';
  }
}