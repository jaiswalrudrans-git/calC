import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/services/account_auth_service.dart';
import '../../converter/screens/converter_home_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../models/chat_contact.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final user = await AccountAuthService.getCurrentUsername();
    final code = await AccountAuthService.getCurrentConnectCode();
    final contactsList = await SecureKeyStorage.getContacts();

    final myUid = await AccountAuthService.getCurrentUserUid();
    final Map<String, LocalChatMessage?> lastMsgs = {};
    for (final contact in contactsList) {
      lastMsgs[contact.uid] = await LocalDatabaseService.getLastMessageForPeer(contact.uid, myUid: myUid);
    }

    if (mounted) {
      setState(() {
        _username = user;
        _connectCode = code;
        _contacts = contactsList;
        _lastMessages = lastMsgs;
        _isLoading = false;
      });
    }

    // Publish connect code to Firebase Spark
    if (code.isNotEmpty) {
      unawaited(SignalCryptoService.publishMyConnectCode());
    }
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
            Text('Connect code $_connectCode copied!'),
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
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
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
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
                          color: AppColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add_rounded, color: AppColors.primary, size: 24),
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
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
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
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
                              if (mounted) {
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
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
              Navigator.pop(ctx);
              await _loadState();
              if (mounted) {
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
      backgroundColor: isDark ? const Color(0xFF0F111A) : const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141724) : Colors.white,
        elevation: 0.5,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded, color: AppColors.primary, size: 20),
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
        backgroundColor: _contacts.length >= 5 ? Colors.grey : AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: Text(_contacts.length >= 5 ? '5/5 Limit' : 'Add Contact'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadState,
              child: ListView(
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
        color: isDark ? const Color(0xFF141724) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: AppColors.primary,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _copyConnectCode,
                icon: const Icon(Icons.copy_rounded, size: 18),
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
        color: isDark ? const Color(0xFF141724) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline_rounded, color: AppColors.primary, size: 42),
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

  Widget _buildContactCard(ChatContact contact, bool isDark) {
    final lastMsg = _lastMessages[contact.uid];
    final lastText = lastMsg != null ? lastMsg.text : 'Encrypted conversation ready';
    final timeStr = lastMsg != null
        ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(lastMsg.timestamp))
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141724) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
          child: Text(
            contact.username.isNotEmpty ? contact.username[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                contact.username,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (timeStr.isNotEmpty)
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
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
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
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
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(contact: contact),
            ),
          ).then((_) => _loadState());
        },
      ),
    );
  }
}
