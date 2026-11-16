class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.moodId,
    required this.createdAt,
    required this.isOutgoing,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final String moodId;
  final DateTime createdAt;
  final bool isOutgoing;

  Map<String, Object?> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'body': body,
        'mood_id': moodId,
        'created_at': createdAt.toIso8601String(),
        'is_outgoing': isOutgoing ? 1 : 0,
      };

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
        id: map['id']! as String,
        conversationId: map['conversation_id']! as String,
        senderId: map['sender_id']! as String,
        body: map['body']! as String,
        moodId: map['mood_id']! as String,
        createdAt: DateTime.parse(map['created_at']! as String),
        isOutgoing: (map['is_outgoing']! as int) == 1,
      );
}
