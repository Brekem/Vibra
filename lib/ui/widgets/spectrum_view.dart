import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/frequency_peak.dart';
import '../../scanner_controller.dart';
import '../app_colors.dart';

/// Gráfico de espectro en tiempo real con eje de frecuencia logarítmico.
class SpectrumView extends StatelessWidget {
  const SpectrumView({super.key, required this.controller, this.height = 220});

  final ScannerController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(child: CustomPaint(painter: _SpectrumPainter(controller))),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.controller) : super(repaint: controller);

  final ScannerController controller;

  static const double minHz = 20;
  static const double maxHz = 20000;
  static const double topDb = 0;
  static const double bottomDb = -100;
  static const double leftPad = 34;
  static const double bottomPad = 20;
  static const double topPad = 8;
  static const double rightPad = 6;

  static const _freqTicks = <double>[50, 100, 200, 500, 1000, 2000, 5000, 10000];

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(leftPad, topPad, size.width - rightPad, size.height - bottomPad);
    if (plot.width <= 0 || plot.height <= 0) return;

    final logRange = math.log(maxHz / minHz);
    double xOf(double f) => plot.left + plot.width * math.log(f / minHz) / logRange;
    double fOf(double x) => minHz * math.exp((x - plot.left) / plot.width * logRange);
    double yOf(double db) =>
        plot.top + plot.height * ((topDb - db) / (topDb - bottomDb)).clamp(0.0, 1.0);

    _drawGrid(canvas, plot, xOf, yOf);

    final analyzer = controller.analyzer;
    final spectrum = analyzer.displayDb;
    final binHz = analyzer.binHz;

    final line = Path();
    const step = 2.0;
    var first = true;
    for (var x = plot.left; x <= plot.right; x += step) {
      final db = _valueForColumn(spectrum, binHz, fOf(x), fOf(math.min(x + step, plot.right)));
      final y = yOf(db);
      if (first) {
        line.moveTo(x, y);
        first = false;
      } else {
        line.lineTo(x, y);
      }
    }

    final fill = Path.from(line)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();

    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.green.withValues(alpha: 0.45),
            AppColors.green.withValues(alpha: 0.04),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.greenDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    final dominant = controller.dominant;
    if (dominant != null) _drawMarker(canvas, plot, dominant, xOf, yOf);

    if (!controller.isScanning && controller.peaks.isEmpty) {
      _drawCenteredText(canvas, plot, 'Pulsa "Escanear" para ver el espectro');
    }
  }

  /// Máximo de los bins que caen en la columna; si no hay ninguno (zona de
  /// graves, donde un bin ocupa varios píxeles) interpola linealmente.
  double _valueForColumn(Float64List db, double binHz, double f0, double f1) {
    final k0 = f0 / binHz;
    final k1 = f1 / binHz;
    final start = k0.ceil();
    final end = math.min(k1.floor(), db.length - 1);
    if (end >= start) {
      var m = db[start];
      for (var k = start + 1; k <= end; k++) {
        if (db[k] > m) m = db[k];
      }
      return m;
    }
    final i = k0.floor().clamp(0, db.length - 2);
    final t = (k0 - i).clamp(0.0, 1.0);
    return db[i] + (db[i + 1] - db[i]) * t;
  }

  void _drawGrid(
    Canvas canvas,
    Rect plot,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    final gridPaint = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    for (var db = topDb; db >= bottomDb; db -= 20) {
      final y = yOf(db);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _drawText(
        canvas,
        '${db.toInt()}',
        Offset(plot.left - 5, y),
        align: TextAlign.right,
        anchor: const Offset(1, 0.5),
      );
    }
    for (final f in _freqTicks) {
      final x = xOf(f);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      _drawText(
        canvas,
        f >= 1000 ? '${(f / 1000).toStringAsFixed(0)}k' : f.toStringAsFixed(0),
        Offset(x, plot.bottom + 4),
        anchor: const Offset(0.5, 0),
      );
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);
    _drawText(canvas, 'dB', Offset(plot.left - 5, plot.bottom + 4), anchor: const Offset(1, 0));
  }

  void _drawMarker(
    Canvas canvas,
    Rect plot,
    FrequencyPeak peak,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    if (peak.frequency < minHz || peak.frequency > maxHz) return;
    final p = Offset(xOf(peak.frequency), yOf(peak.db));
    canvas.drawLine(
      Offset(p.dx, plot.top),
      Offset(p.dx, plot.bottom),
      Paint()
        ..color = AppColors.green.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(p, 6, Paint()..color = Colors.white);
    canvas.drawCircle(p, 4.5, Paint()..color = AppColors.green);

    final label = '${peak.frequency.toStringAsFixed(1)} Hz';
    final tp = _layout(label, 11, Colors.white, FontWeight.w600);
    final bubbleW = tp.width + 12;
    final bubbleH = tp.height + 6;
    var left = p.dx - bubbleW / 2;
    left = left.clamp(plot.left, plot.right - bubbleW);
    var top = p.dy - bubbleH - 10;
    if (top < plot.top) top = p.dy + 10;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, bubbleW, bubbleH),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = AppColors.greenDark);
    tp.paint(canvas, Offset(left + 6, top + 3));
  }

  void _drawCenteredText(Canvas canvas, Rect plot, String text) {
    final tp = _layout(text, 13, AppColors.textMuted, FontWeight.w500);
    tp.paint(canvas, plot.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset at, {
    TextAlign align = TextAlign.left,
    Offset anchor = Offset.zero,
  }) {
    final tp = _layout(text, 10, AppColors.textMuted, FontWeight.w400, align: align);
    tp.paint(canvas, at - Offset(tp.width * anchor.dx, tp.height * anchor.dy));
  }

  TextPainter _layout(
    String text,
    double size,
    Color color,
    FontWeight weight, {
    TextAlign align = TextAlign.left,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
