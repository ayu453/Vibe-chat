import 'dart:async';
import '../models/chat_message.dart';

class MessageStatusUpdate {
  const MessageStatusUpdate(this.messageId, this.status);
  final String messageId;
  final String status;
}

abstract interface class MessageTransport {
  Stream<ChatMessage> get incomingMessages;
  Stream<MessageStatusUpdate> get statusUpdates;
  Future<void> send(ChatMessage message);
  Future<void> dispose();
}

class FakeLocalTransport implements MessageTransport {
  final _controller = StreamController<ChatMessage>.broadcast();
  final _statuses = StreamController<MessageStatusUpdate>.broadcast();
  @override
  Stream<ChatMessage> get incomingMessages => _controller.stream;
  @override
  Stream<MessageStatusUpdate> get statusUpdates => _statuses.stream;
  @override
  Future<void> send(ChatMessage message) async => _statuses.add(MessageStatusUpdate(message.id, 'sent'));
  @override
  Future<void> dispose() async {
    await _controller.close();
    await _statuses.close();
  }
  void simulateIncoming(ChatMessage message) => _controller.add(message);
}
