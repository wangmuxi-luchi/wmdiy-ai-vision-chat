/// Message model for chat conversations.
class ChatMessage {
  final String id;
  final String text;
  final bool isUser; // true = user speech, false = AI reply
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        text: json['text'] as String,
        isUser: json['isUser'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}
