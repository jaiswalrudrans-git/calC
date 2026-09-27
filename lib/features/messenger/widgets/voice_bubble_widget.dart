import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/theme/app_colors.dart';

class VoiceBubbleWidget extends StatefulWidget {
  final LocalChatMessage message;
  final bool isDark;

  const VoiceBubbleWidget({
    super.key,
    required this.message,
    required this.isDark,
  });

  @override
  State<VoiceBubbleWidget> createState() => _VoiceBubbleWidgetState();
}

class _VoiceBubbleWidgetState extends State<VoiceBubbleWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  @override
  void initState() {
    super.initState();
    if (widget.message.duration != null && widget.message.duration! > 0) {
      _duration = Duration(seconds: widget.message.duration!);
    }

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _position = Duration.zero;
          }
        });
      }
    });

    _posSub = _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) {
        setState(() => _duration = dur);
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final path = widget.message.localPath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice note file not available locally')),
      );
      return;
    }

    HapticFeedback.selectionClick();
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play(DeviceFileSource(path));
      }
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds;
    final progress = (totalMs > 0) ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

    final primaryTint = widget.message.isMe
        ? (widget.isDark ? AppColors.tealIcon : AppColors.primary)
        : AppColors.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause Circle Button
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: primaryTint.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: primaryTint,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Waveform / Progress Slider
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: widget.isDark ? Colors.white24 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryTint),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isPlaying ? _formatDuration(_position) : _formatDuration(_duration),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: widget.isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    Icon(
                      Icons.mic_rounded,
                      size: 13,
                      color: widget.isDark ? Colors.white38 : Colors.black38,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
