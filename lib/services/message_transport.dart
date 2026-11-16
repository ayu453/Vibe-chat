import '../models/chat_message.dart';

abstract interface class MessageTransport {
  Stream<ChatMessage> get incomingMessages;
  Future<void> send(ChatMessage message);
  Future<void> dispose();
}

// In-memory transport for UI and architecture testing; it does not reach another device.
class FakeLocalTransport implements MessageTransport {
  final _controller = Stream<ChatMessage>.broadcast();

  @override
  Stream<ChatMessage> get incomingMessages => _controller.stream;

  @override
  Future<void> send(ChatMessage message) async {
    // A future transport can deliver to a remote peer here.
  }

  @override
  Future<void> dispose() => _controller.close();

  void simulateIncoming(ChatMessage message) => _controller.add(message);
}
