import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/security/auth_service.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/services/account_auth_service.dart';
import '../../converter/screens/converter_home_screen.dart';
import '../../settings/screens/settings_screen.dart';
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
  bool _isPaired = false;
  String? _peerUid;
  bool _isLoading = true;

  RealtimeChannel? _pairingSubscription;
  Timer? _inboxPollTimer;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _inboxPollTimer?.cancel();
    final client = SupabaseConfig.client;
    if (client != null && _pairingSubscription != null) {
      try {
        client.removeChannel(_pairingSubscription!);
      } catch (_) {}
      _pairingSubscription = null;
    }
    super.dispose();
  }

  Future<void> _loadState() async {
    final user = await AccountAuthService.getCurrentUsername();
    final code = await AccountAuthService.getCurrentConnectCode();
    final paired = await SecureKeyStorage.isPaired();
    final peer = await SecureKeyStorage.getPairedUid();

    if (mounted) {
      setState(() {
        _username = user;
        _connectCode = code;
        _isPaired = paired;
        _peerUid = peer;
        _isLoading = false;
      });
    }

    // Publish this device's connect code to Supabase pairing_exchange registry
    if (code.isNotEmpty) {
      unawaited(SignalCryptoService.publishMyConnectCode());
      _setupPairingInboxListener(code);
    }

    // Check for incoming pairing invitations or pending messages from peers
    _checkIncomingPairingRequests();
  }

  void _setupPairingInboxListener(String code) {
    final cleanCode = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanCode.length != 6) return;

    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) return;

    if (_pairingSubscription != null) {
      try {
        client.removeChannel(_pairingSubscription!);
      } catch (_) {}
      _pairingSubscription = null;
    }

    final channel = client.channel('pairing_inbox_$cleanCode');
    _pairingSubscription = channel;

    channel.onBroadcast(
      event: 'pairing_invitation',
      callback: (payload) async {
        final senderCode = payload['sender_code'] as String?;
        final senderUid = payload['sender_uid'] as String?;
        final pkBundle = payload['public_key_bundle'] as Map<String, dynamic>?;

        if (senderCode != null && senderCode.isNotEmpty) {
          await SignalCryptoService.pairWithConnectCode(
            senderCode,
            explicitPeerUid: senderUid,
            explicitPeerPublicKeyHex: pkBundle?['identity_key'] as String?,
          );
          if (mounted) {
            final currentPeer = await SecureKeyStorage.getPairedUid();
            setState(() {
              _isPaired = true;
              _peerUid = currentPeer;
            });
            HapticFeedback.mediumImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.link_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Device $senderCode connected with you!')),
                  ],
                ),
                backgroundColor: AppColors.secureGreen,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      },
    );

    channel.subscribe();

    _inboxPollTimer?.cancel();
    _inboxPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _checkIncomingPairingRequests();
    });
  }

  Future<void> _checkIncomingPairingRequests() async {
    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) return;

    try {
      final myUid = await AuthService.getOrCreateDeviceUid();
      final paired = await SecureKeyStorage.isPaired();

      if (paired) return;

      final rows = await client
          .from('messages')
          .select('sender_uid')
          .eq('recipient_uid', myUid)
          .limit(5);

      if (rows.isNotEmpty) {
        final firstSender = rows.first['sender_uid'] as String?;
        if (firstSender != null && firstSender.isNotEmpty) {
          final peRow = await client.from('pairing_exchange').select().eq('uid', firstSender).maybeSingle();
          if (peRow != null) {
            final senderCode = peRow['code'].toString();
            final pkBundle = peRow['public_key_bundle'] as Map<String, dynamic>?;
            await SignalCryptoService.pairWithConnectCode(
              senderCode,
              explicitPeerUid: firstSender,
              explicitPeerPublicKeyHex: pkBundle?['identity_key'] as String?,
            );
            if (mounted) {
              setState(() {
                _isPaired = true;
                _peerUid = firstSender;
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  void _copyConnectCode() {
    if (_connectCode == null) return;
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: _connectCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text('Connect code copied! Share this with contacts.'),
          ],
        ),
        backgroundColor: AppColors.primary,
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
    // Reload state in case user changed settings or logged out
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
                              'Join Chat',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                              ),
                            ),
                            Text(
                              'Enter another device\'s 6-digit Connect Code',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 7,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                    ],
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                    decoration: InputDecoration(
                      hintText: '000-000',
                      counterText: '',
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      errorText: errorMessage,
                    ),
                    onChanged: (val) {
                      if (errorMessage != null) {
                        setSheetState(() => errorMessage = null);
                      }
                      final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.length == 6 && !val.contains('-')) {
                        final formatted = '${digits.substring(0, 3)}-${digits.substring(3, 6)}';
                        controller.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isConnecting ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isConnecting
                              ? null
                              : () async {
                                  final input = controller.text.trim();
                                  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
                                  if (digits.length != 6) {
                                    setSheetState(() {
                                      errorMessage = 'Must be exactly 6 digits';
                                    });
                                    HapticFeedback.vibrate();
                                    return;
                                  }

                                  final myCode = _connectCode?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                                  if (myCode.isNotEmpty && myCode == digits) {
                                    setSheetState(() {
                                      errorMessage = 'Cannot connect to your own device';
                                    });
                                    HapticFeedback.vibrate();
                                    return;
                                  }

                                  setSheetState(() => isConnecting = true);
                                  try {
                                    await SignalCryptoService.initiateUnilateralPairing(digits);
                                    HapticFeedback.mediumImpact();
                                    if (context.mounted) {
                                      Navigator.pop(ctx);
                                      await _loadState();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Connected to device $input!'),
                                            backgroundColor: AppColors.secureGreen,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                        );
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => const ChatScreen()),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    setSheetState(() {
                                      errorMessage = e.toString().replaceFirst('Exception: ', '');
                                      isConnecting = false;
                                    });
                                  }
                                },
                          icon: isConnecting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded, size: 20),
                          label: Text(isConnecting ? 'Connecting...' : 'Connect'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.calculate_outlined),
          tooltip: 'Return to Unit Converter',
          onPressed: _returnToDecoy,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chats',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
            ),
            if (_username != null && _username!.isNotEmpty)
              Text(
                '@$_username',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Enter 6-Digit Connect Code',
            onPressed: _showAddContactDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings & Profile',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadState,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              // Connect Code Banner
              if (_connectCode != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF162345), const Color(0xFF101933)]
                          : [const Color(0xFFEEF4FF), const Color(0xFFE2EDFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? const Color(0xFF283B6B) : const Color(0xFFD0E1FD),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.tag_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'YOUR CONNECT CODE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: _copyConnectCode,
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _connectCode!,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.5,
                          fontFamily: 'monospace',
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Share this permanent code with someone you want to chat with.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                ),

              // Existing Active Chat (if paired)
              if (_isPaired)
                Material(
                  color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 26),
                      ),
                      title: Text(
                        _peerUid != null
                            ? 'Contact (${_peerUid!.replaceAll('code_', '')})'
                            : 'Encrypted Contact',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      subtitle: const Text(
                        'End-to-End Encrypted Channel Active',
                        style: TextStyle(fontSize: 12, color: AppColors.secureGreen),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ChatScreen()),
                        );
                      },
                    ),
                  ),
                )
              else
                // Empty state (no contacts added yet)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 36,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No Conversations Yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your encrypted chat list will appear here once contacts connect with your Connect Code.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _showAddContactDialog,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Enter 6-Digit Connect Code'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddContactDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Connect', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
