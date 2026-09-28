class ChatContact {
  final String uid;
  final String username;
  final String connectCode;
  final String? publicKeyHex;
  final String? lastMessage;
  final int? lastMessageTime;
  final int unreadCount;
  final int addedAt;

  const ChatContact({
    required this.uid,
    required this.username,
    required this.connectCode,
    this.publicKeyHex,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'connect_code': connectCode,
      'public_key': publicKeyHex,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime,
      'unread_count': unreadCount,
      'added_at': addedAt,
    };
  }

  factory ChatContact.fromMap(Map<String, dynamic> map) {
    return ChatContact(
      uid: map['uid'] as String? ?? '',
      username: map['username'] as String? ?? 'Contact',
      connectCode: map['connect_code'] as String? ?? '',
      publicKeyHex: map['public_key'] as String?,
      lastMessage: map['last_message'] as String?,
      lastMessageTime: (map['last_message_time'] as num?)?.toInt(),
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
      addedAt: (map['added_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  ChatContact copyWith({
    String? uid,
    String? username,
    String? connectCode,
    String? publicKeyHex,
    String? lastMessage,
    int? lastMessageTime,
    int? unreadCount,
    int? addedAt,
  }) {
    return ChatContact(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      connectCode: connectCode ?? this.connectCode,
      publicKeyHex: publicKeyHex ?? this.publicKeyHex,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
