import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/notifications/decoy_notification_service.dart';
import '../../auth/services/account_auth_service.dart';
import '../../converter/screens/converter_home_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../models/chat_contact.dart';
import '../services/presence_service.dart';
import 'chat_screen.dart';

class ChatListHomeScreen extends StatefulWidget {
  final VoidCallback? onLoggedOut;

  const ChatListHomeScreen({
    super.key,
    this.onLoggedOut,
  });

  @override
  State<ChatListHomeScreen> createState() => _ChatListHomeScreenState();
}

class _ChatListHomeScreenState extends State<ChatListHomeScreen> {
  String? _username;
  String? _connectCode;
  List<ChatContact> _contacts = [];
  Map<String, LocalChatMessage?> _lastMessages = {};
  Map<String, int> _unreadCounts = {};
  final Map<String, StreamSubscription<DocumentSnapshot>> _peerPresenceSubs = {};
  final Map<String, bool> _onlineContacts = {};
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _userDocSub;
  StreamSubscription<String>? _dbChangeSub;

  @override
  void initState() {
    super.initState();
    PresenceService.instance.enterChatApp();
    _subscribeToDbChanges();
    _loadState();
  }

  void _subscribeToDbChanges() {
    _dbChangeSub?.cancel();
    _dbChangeSub = LocalDatabaseService.onMessageChange.listen((peerUid) {
      if (!mounted) return;
      _refreshUnreadAndLastMessages(peerUid: peerUid.isNotEmpty ? peerUid : null);
    });
  }

  Future<void> _refreshUnreadAndLastMessages({String? peerUid}) async {
    final myUid = await AccountAuthService.getCurrentUserUid();
    final counts = await LocalDatabaseService.getAllUnreadCounts();

    final Map<String, LocalChatMessage?> lastMsgs = Map.from(_lastMessages);
    if (peerUid != null) {
      lastMsgs[peerUid] = await LocalDatabaseService.getLastMessageForPeer(peerUid, myUid: myUid);
    } else {
      for (final contact in _contacts) {
        lastMsgs[contact.uid] = await LocalDatabaseService.getLastMessageForPeer(contact.uid, myUid: myUid);
      }
    }

    // Sort contacts by most recent activity (latest message timestamp, or addedAt)
    final sortedContacts = List<ChatContact>.from(_contacts);
    sortedContacts.sort((a, b) {
      final aTime = lastMsgs[a.uid]?.timestamp ?? a.addedAt;
      final bTime = lastMsgs[b.uid]?.timestamp ?? b.addedAt;
      return bTime.compareTo(aTime);
    });

    if (mounted) {
      setState(() {
        _unreadCounts = counts;
        _lastMessages = lastMsgs;
        _contacts = sortedContacts;
      });
    }
  }

  @override
  void dispose() {
    _dbChangeSub?.cancel();
    _userDocSub?.cancel();
    for (final sub in _peerPresenceSubs.values) {
      sub.cancel();
    }
    _peerPresenceSubs.clear();
    PresenceService.instance.exitChatApp();
    super.dispose();
  }

  Future<void> _loadState() async {
    await FirebaseConfig.init();
    final user = await AccountAuthService.getCurrentUsername();
    final code = await AccountAuthService.getCurrentConnectCode();
    var contactsList = await SecureKeyStorage.getContacts();
    final myUid = await AccountAuthService.getCurrentUserUid();
    final firestore = FirebaseConfig.firestore;

    // Sync with Firestore contacts (both for restoring and discovering peer additions)
    if (myUid != null && myUid.isNotEmpty) {
      if (firestore != null) {
        try {
          final userDoc = await firestore.collection('users').doc(myUid).get();
          if (userDoc.exists) {
            final raw = userDoc.data()?['contacts'] as List<dynamic>?;
            if (raw != null && raw.isNotEmpty) {
              final remoteList = raw
                  .map((e) => ChatContact.fromMap(Map<String, dynamic>.from(e as Map)))
                  .take(5)
                  .toList();
              bool hasNew = false;
              for (final rc in remoteList) {
                final exists = contactsList.any((c) => c.uid == rc.uid);
                if (!exists && contactsList.length < 5) {
                  contactsList.add(rc);
                  await SignalCryptoService.ensureRatchetKeysForContact(rc);
                  hasNew = true;
                }
              }
              if (hasNew || (contactsList.isEmpty && remoteList.isNotEmpty)) {
                await SecureKeyStorage.saveContacts(contactsList);
              }
            }
          }
        } catch (_) {}

        // Listen for realtime contact updates from peers
        _userDocSub ??= firestore.collection('users').doc(myUid).snapshots().listen((snap) async {
          if (!snap.exists || !mounted) return;
          final raw = snap.data()?['contacts'] as List<dynamic>?;
          if (raw == null) return;
          final remoteList = raw
              .map((e) => ChatContact.fromMap(Map<String, dynamic>.from(e as Map)))
              .take(5)
              .toList();
          final current = await SecureKeyStorage.getContacts();
          bool changed = false;
          for (final rc in remoteList) {
            if (!current.any((c) => c.uid == rc.uid) && current.length < 5) {
              current.add(rc);
              await SignalCryptoService.ensureRatchetKeysForContact(rc);
              changed = true;
            }
          }
          if (changed) {
            await SecureKeyStorage.saveContacts(current);
            _loadState();
          }
        });
      }
    }

    final Map<String, LocalChatMessage?> lastMsgs = {};
    for (final contact in contactsList) {
      lastMsgs[contact.uid] = await LocalDatabaseService.getLastMessageForPeer(contact.uid, myUid: myUid);
    }

    final unreadCounts = await LocalDatabaseService.getAllUnreadCounts();

    // Sort contacts by most recent activity (latest message timestamp, or addedAt)
    contactsList.sort((a, b) {
      final aTime = lastMsgs[a.uid]?.timestamp ?? a.addedAt;
      final bTime = lastMsgs[b.uid]?.timestamp ?? b.addedAt;
      return bTime.compareTo(aTime);
    });

    if (firestore != null) {
      for (final contact in contactsList) {
        if (!_peerPresenceSubs.containsKey(contact.uid)) {
          _peerPresenceSubs[contact.uid] = firestore.collection('users').doc(contact.uid).snapshots().listen((snap) {
            if (!mounted) return;
            final isOnline = snap.exists ? (snap.data()?['is_online'] as bool? ?? false) : false;
            if (_onlineContacts[contact.uid] != isOnline) {
              setState(() {
                _onlineContacts[contact.uid] = isOnline;
              });
            }
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _username = user;
        _connectCode = code;
        _contacts = contactsList;
        _lastMessages = lastMsgs;
        _unreadCounts = unreadCounts;
        _isLoading = false;
      });
    }

    // Publish connect code to Firebase Spark
    if (code.isNotEmpty) {
      unawaited(SignalCryptoService.publishMyConnectCode());
    }

    // Start realtime listener across user contacts
    if (myUid != null && myUid.isNotEmpty && contactsList.isNotEmpty) {
      DecoyNotificationService.instance.startRealtimeListener(myUid: myUid, contacts: contactsList);
    }

    // Check for pending conversation from tapped decoy notification
    final pendingChannel = DecoyNotificationService.instance.consumePendingConversationId();
    if (pendingChannel != null && mounted && myUid != null) {
      final targetContact = contactsList.firstWhere(
        (c) {
          final participants = [myUid, c.uid]..sort();
          final ch = 'ch_${participants.join('_')}';
          return ch == pendingChannel;
        },
        orElse: () => const ChatContact(uid: '', username: '', connectCode: '', addedAt: 0),
      );
      if (targetContact.uid.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openChat(targetContact);
          }
        });
      }
    }
  }

  void _openChat(ChatContact contact) {
    if ((_unreadCounts[contact.uid] ?? 0) > 0) {
      setState(() {
        _unreadCounts[contact.uid] = 0;
      });
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(contact: contact),
      ),
    ).then((_) => _loadState());
  }

  void _copyConnectCode() {
    if (_connectCode == null || _connectCode!.isEmpty) return;
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _connectCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Connect code $_connectCode copied!'),
            ),
          ],
        ),
        backgroundColor: AppColors.secureGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openSettings() async {
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
    final stillLoggedIn = await AccountAuthService.isLoggedIn();
    if (!stillLoggedIn && widget.onLoggedOut != null) {
      widget.onLoggedOut!();
    } else {
      _loadState();
    }
  }

  void _returnToDecoy() {
    HapticFeedback.selectionClick();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ConverterHomeScreen()),
      );
    }
  }

  void _showAddContactDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Strict 5-contact check
    if (_contacts.length >= SecureKeyStorage.maxContactsLimit) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.people_alt_rounded, color: AppColors.alertRed),
              SizedBox(width: 10),
              Text('Contact Limit Reached'),
            ],
          ),
          content: const Text(
            'You can connect with up to 5 people on the free Spark plan.\n\nTo add a new contact, please remove an existing contact first.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
              ),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController();
    String? errorMessage;
    bool isConnecting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (sbCtx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sbCtx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F0F0F) : AppColors.surfaceLight,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: isDark ? MetricGlass.border : AppColors.cardBorderLight, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? MetricGlass.level2 : Colors.grey.shade100,
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? MetricGlass.border : Colors.grey.shade300, width: 1),
                        ),
                        child: Icon(Icons.person_add_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add Contact',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                              ),
                            ),
                            Text(
                              'Slot ${_contacts.length + 1} of 5 available',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Enter your friend\'s 6-digit permanent connect code to establish an encrypted Signal chat.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 7,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '000-000',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white24 : Colors.black26,
                        letterSpacing: 6,
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF141724) : const Color(0xFFF1F4F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isDark ? Colors.white : Colors.black, width: 2),
                      ),
                    ),
                    onChanged: (val) {
                      final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
                      if (clean.length == 6 && !val.contains('-')) {
                        final formatted = '${clean.substring(0, 3)}-${clean.substring(3, 6)}';
                        controller.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }
                    },
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.alertRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.alertRed, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: AppColors.alertRed, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isConnecting
                        ? null
                        : () async {
                            final raw = controller.text.trim();
                            final clean = raw.replaceAll(RegExp(r'[^0-9]'), '');
                            if (clean.length != 6) {
                              setSheetState(() => errorMessage = 'Please enter a valid 6-digit code.');
                              return;
                            }

                            setSheetState(() {
                              isConnecting = true;
                              errorMessage = null;
                            });

                            try {
                              final contact = await SignalCryptoService.initiateUnilateralPairing(clean);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadState();
                              if (mounted && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Connected with ${contact.username}!'),
                                    backgroundColor: AppColors.secureGreen,
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(contact: contact),
                                  ),
                                ).then((_) => _loadState());
                              }
                            } catch (e) {
                              setSheetState(() {
                                isConnecting = false;
                                errorMessage = e.toString().replaceAll('Exception: ', '');
                              });
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isConnecting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.black : Colors.white),
                          )
                        : const Text(
                            'Connect',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _removeContact(ChatContact contact) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Contact'),
        content: Text(
          'Remove "${contact.username}" from your contacts?\n\nThis will free up a contact slot (Limit: 5 contacts).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await SecureKeyStorage.removeContact(contact.uid);
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadState();
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Removed ${contact.username}')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.alertRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? MetricColors.background : const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: isDark ? MetricColors.background : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level2 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? MetricGlass.border : Colors.transparent, width: 1),
              ),
              child: Icon(Icons.lock_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Messages',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_contacts.length}/5 Contacts',
                    style: TextStyle(
                      fontSize: 11,
                      color: _contacts.length >= 5
                          ? AppColors.alertRed
                          : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Decoy exit button (returns to calculator disguise)
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'Return to Calculator',
            onPressed: _returnToDecoy,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddContactDialog,
        backgroundColor: _contacts.length >= 5
            ? (isDark ? MetricGlass.level1 : Colors.grey)
            : (isDark ? Colors.white : Colors.black),
        foregroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        icon: const Icon(Icons.person_add_rounded, size: 18),
        label: Text(
          _contacts.length >= 5 ? '5/5 Limit' : 'Add Contact',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadState,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  // My Connect Code Banner
                  _buildMyCodeBanner(isDark),
                  const SizedBox(height: 20),

                  // Contacts Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MY CONTACTS (${_contacts.length}/5)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                      if (_contacts.length < 5)
                        Text(
                          '${5 - _contacts.length} slots left',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.secureGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Empty State or Contact List
                  if (_contacts.isEmpty)
                    _buildEmptyState(isDark)
                  else
                    ..._contacts.map((contact) => _buildContactCard(contact, isDark)),
                ],
              ),
            ),
    );
  }

  Widget _buildMyCodeBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? MetricGlass.level1 : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _username != null && _username!.isNotEmpty
                      ? 'CONNECT CODE ($_username)'
                      : 'YOUR CONNECT CODE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.secureGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_rounded, color: AppColors.secureGreen, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Firebase Spark',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secureGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _connectCode ?? '--- ---',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: isDark ? MetricColors.textPrimary : Colors.black87,
                  ),
                ),
              ),
              IconButton(
                onPressed: _copyConnectCode,
                icon: Icon(Icons.copy_rounded, size: 18, color: isDark ? MetricColors.textSecondary : Colors.black54),
                tooltip: 'Copy Code',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Share this code with friends so they can add you (up to 5 contacts).',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? MetricGlass.level1 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? MetricGlass.level2 : Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(color: isDark ? MetricGlass.border : Colors.grey.shade300, width: 1.0),
            ),
            child: Icon(Icons.people_outline_rounded, color: isDark ? MetricColors.textSecondary : Colors.black54, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            'No Contacts Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Contact" below and enter a 6-digit Connect Code to start chatting.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  static final DateFormat _cardTimeFormat = DateFormat('hh:mm a');

  Widget _buildContactCard(ChatContact contact, bool isDark) {
    final lastMsg = _lastMessages[contact.uid];
    final unreadCount = _unreadCounts[contact.uid] ?? 0;
    final hasUnread = unreadCount > 0;
    final lastText = lastMsg != null ? lastMsg.text : 'Encrypted conversation ready';
    final timeStr = lastMsg != null
        ? _cardTimeFormat.format(DateTime.fromMillisecondsSinceEpoch(lastMsg.timestamp))
        : '';

    return RepaintBoundary(
      key: ValueKey(contact.uid),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? MetricGlass.level1 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUnread
              ? (isDark ? AppColors.alertRed.withValues(alpha: 0.4) : AppColors.alertRed.withValues(alpha: 0.3))
              : (isDark ? MetricGlass.border : AppColors.cardBorderLight),
          width: hasUnread ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isDark ? MetricGlass.level2 : Colors.grey.shade200,
                child: Text(
                  contact.username.isNotEmpty ? contact.username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: isDark ? MetricColors.textPrimary : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (_onlineContacts[contact.uid] == true)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: MetricChatColors.onlineGreen,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? MetricColors.background : Colors.white,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.username,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.bold,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_onlineContacts[contact.uid] == true) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: MetricChatColors.onlineGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Online',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: MetricChatColors.onlineGreen,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                    color: hasUnread
                        ? AppColors.alertRed
                        : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              lastText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                color: hasUnread
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasUnread) ...[
                Container(
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.alertRed,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.alertRed.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (val) {
                  if (val == 'remove') {
                    _removeContact(contact);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: AppColors.alertRed, size: 20),
                        SizedBox(width: 8),
                        Text('Remove Contact', style: TextStyle(color: AppColors.alertRed)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => _openChat(contact),
        ),
      ),
    ),
  );
}
}
