// Deprecated: Shared gallery has been disabled as media transferability is removed.
import 'package:flutter/material.dart';

class SharedGalleryScreen extends StatelessWidget {
  const SharedGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Gallery is disabled.')),
    );
  }
}
