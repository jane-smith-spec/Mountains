import 'package:flutter/material.dart';

class PhotoViewScreen extends StatelessWidget {
  const PhotoViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photo View')),
      body: const Center(
        child: Text('Photo analysis mode will be implemented in a follow-up step.'),
      ),
    );
  }
}
