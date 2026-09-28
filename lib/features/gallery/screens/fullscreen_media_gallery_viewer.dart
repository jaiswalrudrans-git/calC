// Deprecated: FullScreenMediaGalleryViewer has been disabled as media transferability is removed.
import 'package:flutter/material.dart';

class FullScreenMediaGalleryViewer extends StatelessWidget {
  const FullScreenMediaGalleryViewer({super.key, dynamic items, dynamic initialIndex});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Viewer is disabled.')),
    );
  }
}
