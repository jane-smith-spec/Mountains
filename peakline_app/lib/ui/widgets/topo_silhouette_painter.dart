import 'package:flutter/material.dart';

class TopoSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = Colors.lightGreenAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final Path path = Path()..moveTo(0, size.height * 0.7);
    path.cubicTo(
      size.width * 0.15,
      size.height * 0.45,
      size.width * 0.35,
      size.height * 0.85,
      size.width * 0.55,
      size.height * 0.5,
    );
    path.cubicTo(
      size.width * 0.72,
      size.height * 0.35,
      size.width * 0.88,
      size.height * 0.75,
      size.width,
      size.height * 0.55,
    );

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant TopoSilhouettePainter oldDelegate) => false;
}

