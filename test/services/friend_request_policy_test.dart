import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_chat/services/friend_request_policy.dart';

void main() {
  test('request remains closed until recipient accepts', () {
    expect(FriendRequestPolicy.canOpenChat(status: 'requested', keyChanged: false), isFalse);
    expect(FriendRequestPolicy.canAccept(status: 'requested', direction: 'incoming'), isTrue);
    expect(FriendRequestPolicy.canOpenChat(status: 'accepted', keyChanged: false), isTrue);
  });

  test('blocked and key-changed contacts cannot receive or send chat traffic', () {
    expect(FriendRequestPolicy.shouldDropEnvelope(status: 'blocked', keyChanged: false), isTrue);
    expect(FriendRequestPolicy.shouldDropEnvelope(status: 'accepted', keyChanged: true), isTrue);
    expect(FriendRequestPolicy.canOpenChat(status: 'accepted', keyChanged: true), isFalse);
    expect(FriendRequestPolicy.canAccept(status: 'requested', direction: 'outgoing'), isFalse);
  });
}
