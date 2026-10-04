import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:metric/core/database/local_cache.dart';
import 'package:metric/features/messenger/models/chat_contact.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDatabaseService.clearAllMessages();
  });

  group('Unread Count & Sorting Tests', () {
    test('Unread counts accurately track received vs sent vs read messages per peer', () async {
      const peerA = 'peer_user_a';
      const peerB = 'peer_user_b';
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Initial unread counts should be 0
      expect(await LocalDatabaseService.getUnreadCountForPeer(peerA), equals(0));
      expect(await LocalDatabaseService.getUnreadCountForPeer(peerB), equals(0));

      // 2. Peer A sends 2 messages (status = 'delivered', isMe = false)
      await LocalDatabaseService.saveMessage(LocalChatMessage(
        id: 'msg_a_1',
        senderUid: peerA,
        receiverUid: 'my_uid',
        text: 'Hello from A 1',
        timestamp: now - 5000,
        isMe: false,
        status: 'delivered',
      ));

      await LocalDatabaseService.saveMessage(LocalChatMessage(
        id: 'msg_a_2',
        senderUid: peerA,
        receiverUid: 'my_uid',
        text: 'Hello from A 2',
        timestamp: now - 4000,
        isMe: false,
        status: 'delivered',
      ));

      // 3. User sends 1 message to Peer A (isMe = true, status = 'sent') -> should NOT count as unread!
      await LocalDatabaseService.saveMessage(LocalChatMessage(
        id: 'msg_my_1',
        senderUid: 'my_uid',
        receiverUid: peerA,
        text: 'My reply to A',
        timestamp: now - 3000,
        isMe: true,
        status: 'sent',
      ));

      // 4. Peer B sends 1 message (status = 'delivered')
      await LocalDatabaseService.saveMessage(LocalChatMessage(
        id: 'msg_b_1',
        senderUid: peerB,
        receiverUid: 'my_uid',
        text: 'Hello from B',
        timestamp: now - 2000,
        isMe: false,
        status: 'delivered',
      ));

      // Verify unread counts per peer
      expect(await LocalDatabaseService.getUnreadCountForPeer(peerA), equals(2));
      expect(await LocalDatabaseService.getUnreadCountForPeer(peerB), equals(1));

      // Verify batch unread counts
      final batchCounts = await LocalDatabaseService.getAllUnreadCounts();
      expect(batchCounts[peerA], equals(2));
      expect(batchCounts[peerB], equals(1));

      // 5. Open chat with Peer A -> markAllReceivedMessagesAsRead(peerA)
      await LocalDatabaseService.markAllReceivedMessagesAsRead(peerA);

      // Verify Peer A count is reset to 0, while Peer B count remains untouched at 1
      expect(await LocalDatabaseService.getUnreadCountForPeer(peerA), equals(0));
      expect(await LocalDatabaseService.getUnreadCountForPeer(peerB), equals(1));

      final updatedBatch = await LocalDatabaseService.getAllUnreadCounts();
      expect(updatedBatch[peerA] ?? 0, equals(0));
      expect(updatedBatch[peerB], equals(1));
    });

    test('LocalDatabaseService.onMessageChange stream emits on save and mark-read events', () async {
      const peerA = 'peer_user_stream';
      final receivedEvents = <String>[];

      final sub = LocalDatabaseService.onMessageChange.listen((peerUid) {
        receivedEvents.add(peerUid);
      });

      // Save incoming message
      await LocalDatabaseService.saveMessage(LocalChatMessage(
        id: 'stream_msg_1',
        senderUid: peerA,
        receiverUid: 'my_uid',
        text: 'Stream test message',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isMe: false,
        status: 'delivered',
      ));

      // Mark as read
      await LocalDatabaseService.markAllReceivedMessagesAsRead(peerA);

      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(receivedEvents, contains(peerA));
      expect(receivedEvents.length, greaterThanOrEqualTo(2));
    });

    test('Contacts sort order places most recent activity at index 0', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      final contactA = ChatContact(
        uid: 'uid_a',
        username: 'Alice',
        connectCode: '111222',
        addedAt: now - 100000,
      );

      final contactB = ChatContact(
        uid: 'uid_b',
        username: 'Bob',
        connectCode: '333444',
        addedAt: now - 90000,
      );

      final lastMsgs = <String, LocalChatMessage?>{
        'uid_a': LocalChatMessage(
          id: 'm1',
          senderUid: 'uid_a',
          receiverUid: 'my_uid',
          text: 'Recent message from Alice',
          timestamp: now - 1000, // Newer message!
          isMe: false,
        ),
        'uid_b': LocalChatMessage(
          id: 'm2',
          senderUid: 'uid_b',
          receiverUid: 'my_uid',
          text: 'Older message from Bob',
          timestamp: now - 50000, // Older message
          isMe: false,
        ),
      };

      final contacts = [contactB, contactA]; // Bob initially first

      contacts.sort((a, b) {
        final aTime = lastMsgs[a.uid]?.timestamp ?? a.addedAt;
        final bTime = lastMsgs[b.uid]?.timestamp ?? b.addedAt;
        return bTime.compareTo(aTime);
      });

      // Alice should now be first because she has the newest message
      expect(contacts.first.uid, equals('uid_a'));
      expect(contacts.last.uid, equals('uid_b'));
    });
  });
}
