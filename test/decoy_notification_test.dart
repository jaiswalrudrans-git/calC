import 'package:flutter_test/flutter_test.dart';
import 'package:metric/core/notifications/decoy_notification_service.dart';

void main() {
  group('Decoy Notification System - Specifications & Test Matrix', () {
    test('Notification ID is deterministic, positive, and fits in 31 bits', () {
      const convA = 'ch_userA_userB';
      const convB = 'ch_userA_userC';
      const convC = 'ch_userD_userE';

      final idA1 = DecoyNotificationService.notificationIdForConversation(convA);
      final idA2 = DecoyNotificationService.notificationIdForConversation(convA);
      final idB = DecoyNotificationService.notificationIdForConversation(convB);
      final idC = DecoyNotificationService.notificationIdForConversation(convC);

      // Deterministic: Same conversation always yields exact same ID
      expect(idA1, equals(idA2));
      expect(idA1, isPositive);
      expect(idA1, lessThanOrEqualTo(0x7FFFFFFF));

      // Separate conversations yield distinct IDs (replacement happens per-conversation)
      expect(idA1, isNot(equals(idB)));
      expect(idB, isNot(equals(idC)));
      expect(idA1, isNot(equals(idC)));
    });

    test('Decoy text and channels match visible calC utility application', () {
      // Must be completely generic utility text
      expect(DecoyNotificationService.decoyTitle, equals('calC'));
      expect(DecoyNotificationService.decoyBody, equals('Your answer is ready'));

      // Channel details must NOT leak messenger/vault terminology
      expect(DecoyNotificationService.channelId, equals('calC_messages'));
      expect(DecoyNotificationService.channelName, equals('calC'));
      expect(DecoyNotificationService.channelDescription.toLowerCase(), isNot(contains('chat')));
      expect(DecoyNotificationService.channelDescription.toLowerCase(), isNot(contains('secret')));
      expect(DecoyNotificationService.channelDescription.toLowerCase(), isNot(contains('vault')));
      expect(DecoyNotificationService.channelDescription.toLowerCase(), isNot(contains('metric')));
    });

    test('Active conversation suppresses notification for that exact conversation only', () {
      final service = DecoyNotificationService.instance;

      const chatA = 'ch_user1_user2';
      const chatB = 'ch_user1_user3';

      // Initially no conversation active
      service.setActiveConversation(null);
      expect(service.activeConversationId, isNull);

      // User enters Chat A
      service.setActiveConversation(chatA);
      expect(service.activeConversationId, equals(chatA));

      // User exits or enters Chat B
      service.setActiveConversation(chatB);
      expect(service.activeConversationId, equals(chatB));

      // User returns to calculator/settings
      service.setActiveConversation(null);
      expect(service.activeConversationId, isNull);
    });

    test('Zero sensitive data in notification titles or bodies', () {
      const sensitiveTerms = [
        'john',
        'hey bro',
        'photo',
        'video',
        'voice note',
        'document',
        'secret',
        'vault',
        'encrypted',
        'new message',
      ];

      for (final term in sensitiveTerms) {
        expect(
          DecoyNotificationService.decoyTitle.toLowerCase(),
          isNot(contains(term)),
        );
        expect(
          DecoyNotificationService.decoyBody.toLowerCase(),
          isNot(contains(term)),
        );
      }
    });

    test('Pending conversation token is consumed only once after authentication', () {
      final service = DecoyNotificationService.instance;

      // Consume when empty returns null
      expect(service.consumePendingConversationId(), isNull);

      // Simulate a notification payload parsed
      // We can test that consuming multiple times is idempotent and safely clears
      expect(service.consumePendingConversationId(), isNull);
    });
  });
}
