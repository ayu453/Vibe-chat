class FriendRequestPolicy {
  static bool canOpenChat({required String status, required bool keyChanged}) =>
      status == 'accepted' && !keyChanged;

  static bool shouldDropEnvelope({required String? status, required bool keyChanged}) =>
      status == 'blocked' || keyChanged;

  static bool canAccept({required String status, required String direction}) =>
      status == 'requested' && direction == 'incoming';
}
