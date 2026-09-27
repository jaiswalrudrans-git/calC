import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:metric/core/database/local_cache.dart';

void main() {
  group('Step 4 - Media Gallery Organization & Grouping Tests', () {
    test('Groups media messages chronologically by Month Year with newest first', () {
      final sept2026 = DateTime(2026, 9, 15, 14, 30).millisecondsSinceEpoch;
      final aug2026 = DateTime(2026, 8, 20, 10, 0).millisecondsSinceEpoch;
      final jul2026 = DateTime(2026, 7, 4, 18, 45).millisecondsSinceEpoch;

      final messages = [
        LocalChatMessage(
          id: 'm1',
          senderUid: 'u1',
          receiverUid: 'u2',
          text: 'august_doc.pdf',
          timestamp: aug2026,
          isMe: true,
          mediaType: 'document',
        ),
        LocalChatMessage(
          id: 'm2',
          senderUid: 'u1',
          receiverUid: 'u2',
          text: 'september_photo.jpg',
          timestamp: sept2026,
          isMe: false,
          mediaType: 'image',
        ),
        LocalChatMessage(
          id: 'm3',
          senderUid: 'u1',
          receiverUid: 'u2',
          text: 'july_voice.m4a',
          timestamp: jul2026,
          isMe: true,
          mediaType: 'voice',
        ),
        LocalChatMessage(
          id: 'm4',
          senderUid: 'u1',
          receiverUid: 'u2',
          text: 'september_video.mp4',
          timestamp: sept2026 + 1000,
          isMe: true,
          mediaType: 'video',
        ),
      ];

      // Sorting newest first
      final sorted = List<LocalChatMessage>.from(messages)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final Map<String, List<LocalChatMessage>> grouped = {};
      for (final item in sorted) {
        final date = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
        final key = DateFormat('MMMM yyyy').format(date);
        grouped.putIfAbsent(key, () => []).add(item);
      }

      final monthKeys = grouped.keys.toList();
      expect(monthKeys.length, equals(3));
      expect(monthKeys[0], equals('September 2026'));
      expect(monthKeys[1], equals('August 2026'));
      expect(monthKeys[2], equals('July 2026'));

      expect(grouped['September 2026']!.length, equals(2));
      expect(grouped['August 2026']!.length, equals(1));
      expect(grouped['July 2026']!.length, equals(1));
    });

    test('Filters Photos and Videos correctly into media tab', () {
      final messages = [
        LocalChatMessage(id: '1', senderUid: 'u1', receiverUid: 'u2', text: 'img1.jpg', timestamp: 100, isMe: true, mediaType: 'image'),
        LocalChatMessage(id: '2', senderUid: 'u1', receiverUid: 'u2', text: 'vid1.mp4', timestamp: 200, isMe: true, mediaType: 'video'),
        LocalChatMessage(id: '3', senderUid: 'u1', receiverUid: 'u2', text: 'doc1.pdf', timestamp: 300, isMe: false, mediaType: 'document'),
        LocalChatMessage(id: '4', senderUid: 'u1', receiverUid: 'u2', text: 'voice1.m4a', timestamp: 400, isMe: false, mediaType: 'voice'),
        LocalChatMessage(id: '5', senderUid: 'u1', receiverUid: 'u2', text: 'regular message', timestamp: 500, isMe: true),
      ];

      final photosAndVideos = messages.where((m) => m.mediaType == 'image' || m.mediaType == 'video').toList();
      final documents = messages.where((m) => m.mediaType == 'document').toList();
      final voiceNotes = messages.where((m) => m.mediaType == 'voice').toList();

      expect(photosAndVideos.length, equals(2));
      expect(photosAndVideos.map((m) => m.id), containsAll(['1', '2']));

      expect(documents.length, equals(1));
      expect(documents.first.id, equals('3'));

      expect(voiceNotes.length, equals(1));
      expect(voiceNotes.first.id, equals('4'));
    });
  });
}
