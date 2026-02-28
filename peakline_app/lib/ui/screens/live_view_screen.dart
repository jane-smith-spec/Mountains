import 'package:flutter/material.dart';

class LiveViewScreen extends StatelessWidget {
  const LiveViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live View')),
      body: const Center(
        child: Text('Live AR camera view will be implemented in a follow-up step.'),
      ),
    );
  }
}
