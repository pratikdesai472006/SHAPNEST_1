import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/node_data.dart';
import '../../models/shapnest_protocol.dart';
import '../../services/ble_service.dart';

class RadarView extends StatefulWidget {
  final List<NodeData> nodes;
  final TrackingSource trackingSource;
  final String unit; // 'm' or 'cm'

  const RadarView({
    super.key,
    required this.nodes,
    required this.trackingSource,
    required this.unit,
  });

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 300),
          painter: RadarPainter(
            nodes: widget.nodes,
            trackingSource: widget.trackingSource,
            unit: widget.unit,
            sweepAngle: _animController.value * 2 * pi,
            pulseValue: _animController.value,
          ),
        );
      },
    );
  }
}

class RadarPainter extends CustomPainter {
  final List<NodeData> nodes;
  final TrackingSource trackingSource;
  final String unit;
  final double sweepAngle;
  final double pulseValue;

  RadarPainter({
    required this.nodes,
    required this.trackingSource,
    required this.unit,
    required this.sweepAngle,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width / 2, size.height / 2) - 24;

    // 1. Radar Background Glow
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF0F172A).withValues(alpha: 0.9),
          const Color(0xFF020617),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, bgPaint);

    // 2. Concentric Distance Grid Rings
    // Representing 1.0m, 2.0m, 3.0m, 5.0m, 8.0m (max)
    final ringDistancesM = [1.0, 2.0, 3.5, 5.0, 8.0];
    final ringPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final dist in ringDistancesM) {
      final r = (dist / ShapnestProtocol.distanceMaxM) * maxRadius;
      canvas.drawCircle(center, r, ringPaint);

      // Ring Distance Text Label
      final label = unit == 'm' ? '${dist.toStringAsFixed(1)}m' : '${(dist * 100).toInt()}cm';
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(center.dx + 4, center.dy - r - 12));
    }

    // 3. Crosshairs
    final crossHairPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), crossHairPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), crossHairPaint);

    // 4. Rotating Radar Sweep Line
    final sweepEnd = Offset(
      center.dx + maxRadius * cos(sweepAngle),
      center.dy + maxRadius * sin(sweepAngle),
    );
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: sweepAngle - 0.5,
        endAngle: sweepAngle,
        colors: [
          Colors.transparent,
          const Color(0xFF00E5FF).withValues(alpha: 0.25),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, sweepPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    canvas.drawLine(center, sweepEnd, linePaint);

    // 5. Center Avatar (Phone or Child Wristband)
    final centerGlow = Paint()
      ..color = (trackingSource == TrackingSource.directPhone ? const Color(0xFF38BDF8) : const Color(0xFFA855F7))
          .withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 18 + pulseValue * 6, centerGlow);

    final centerDot = Paint()
      ..color = (trackingSource == TrackingSource.directPhone ? const Color(0xFF38BDF8) : const Color(0xFFA855F7))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, centerDot);

    // 6. Draw Nodes (Fan, Iron, Door at radial bearings: 90°, 210°, 330°)
    final angles = [
      -pi / 2, // Top (Fan)
      pi / 6, // Bottom right (Iron)
      5 * pi / 6, // Bottom left (Door)
    ];

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final angle = angles[i % angles.length];

      final distM = (trackingSource == TrackingSource.directPhone) ? node.directDistanceM : node.wbDistanceM;
      final state = (trackingSource == TrackingSource.directPhone) ? node.directState : node.wbState;

      final isOnline = state != NodeState.offline && distM != null;

      // Position along radius
      final effectiveDist = isOnline ? distM.clamp(0.15, ShapnestProtocol.distanceMaxM) : ShapnestProtocol.distanceMaxM;
      final r = (effectiveDist / ShapnestProtocol.distanceMaxM) * maxRadius;

      final nodePos = Offset(
        center.dx + r * cos(angle),
        center.dy + r * sin(angle),
      );

      final isDanger = isOnline && node.isDanger(distM);

      // Node Marker Glow
      if (isOnline) {
        final nodeGlow = Paint()
          ..color = (isDanger ? const Color(0xFFFF5252) : node.primaryColor)
              .withValues(alpha: isDanger ? 0.6 : 0.35)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(nodePos, 14 + (isDanger ? pulseValue * 8 : 0), nodeGlow);
      }

      // Node Marker Core
      final nodeCore = Paint()
        ..color = isOnline
            ? (isDanger ? const Color(0xFFFF5252) : node.primaryColor)
            : const Color(0xFF64748B)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(nodePos, isOnline ? 9 : 6, nodeCore);

      // Node Label & Distance Tag
      final distStr = isOnline
          ? (unit == 'm' ? '${distM.toStringAsFixed(2)}m' : '${(distM * 100).toInt()}cm')
          : 'OFFLINE';

      final tagSpan = TextSpan(
        children: [
          TextSpan(
            text: '${node.name}\n',
            style: TextStyle(
              color: isOnline ? Colors.white : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: distStr,
            style: TextStyle(
              color: isDanger
                  ? const Color(0xFFFF5252)
                  : (isOnline ? node.primaryColor : Colors.white38),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
      final tagPainter = TextPainter(
        text: tagSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      // Position text slightly away from center
      final textOffset = Offset(
        nodePos.dx - (tagPainter.width / 2),
        nodePos.dy + (nodePos.dy >= center.dy ? 12 : -tagPainter.height - 12),
      );
      tagPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return true;
  }
}
