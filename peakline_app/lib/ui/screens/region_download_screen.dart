import 'package:flutter/material.dart';

class RegionDownloadScreen extends StatelessWidget {
  const RegionDownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Region Download')),
      body: const Center(
        child: Text('DEM region browsing/downloading will be implemented in a follow-up step.'),
      ),
    );
  }
}
