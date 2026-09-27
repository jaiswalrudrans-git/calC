import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/security/privacy_guard.dart';

class ImageViewerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final int timestamp;
  final String heroTag;

  const ImageViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
    required this.timestamp,
    required this.heroTag,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    PrivacyGuard.setScreenProtection(true);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    PrivacyGuard.setScreenProtection(false);
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformationController.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0)
        ..setTranslationRaw(-position.dx * 1.5, -position.dy * 1.5, 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('MMM d, yyyy • hh:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(widget.timestamp),
    );
    final file = File(widget.filePath);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Interactive Zoomable Image
          GestureDetector(
            onTap: () => setState(() => _showOverlay = !_showOverlay),
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: _handleDoubleTap,
            child: SizedBox.expand(
              child: Center(
                child: Hero(
                  tag: widget.heroTag,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 4.5,
                    child: file.existsSync()
                        ? Image.file(
                            file,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Text(
                                'Failed to load sandboxed image',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          )
                        : const Center(
                            child: Text(
                              'Media file not found in sandbox',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),

          // Top Header Overlay
          if (_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  bottom: 12,
                  left: 8,
                  right: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
