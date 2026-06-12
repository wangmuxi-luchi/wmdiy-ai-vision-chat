abstract class CommandReceiverService {
  Stream<Command> get commandStream;
  
  void sendCameraImage();
  
  void dispose();
}

class Command {
  final String type;
  final Map<String, dynamic>? data;
  
  Command({required this.type, this.data});
  
  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
    };
  }
}