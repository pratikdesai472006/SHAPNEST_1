import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/node_data.dart';
import '../../models/shapnest_protocol.dart';
import '../../services/ble_service.dart';

class RadarView extends StatefulWidget {
  final List<NodeData> nodes;
  final TrackingSource trackingSource;

  const RadarView({
    super.key,
    required this.nodes,
    required this.trackingSource,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 300),
          painter: RadarPainter(
            nodes: widget.nodes,
            trackingSource: widget.trackingSource,
            sweepAngle: _animController.value * 2 * pi,
            pulseValue: _animController.value,
            isDark: isDark,
          ),
        );
      },
    );
  }
}

class RadarPainter extends CustomPainter {
  final List<NodeData> nodes;
  final TrackingSource trackingSource;
  final double sweepAngle;
  final double pulseValue;
  final bool isDark;

  RadarPainter({
    required this.nodes,
    required this.trackingSource,
    required this.sweepAngle,
    required this.pulseValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width / 2, size.height / 2) - 24;

    // 1. Radar Background Radial Fill
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [
                const Color(0xFF0F172A).withValues(alpha: 0.9),
                const Color(0xFF020617),
              ]
            : [
                Colors.white,
                const Color(0xFFE2E8F0),
              ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, bgPaint);

    // Subtle outline border around the entire radar disc
    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, maxRadius, borderPaint);

    // 2. Three Concentric Signal Strength Grid Rings:
    // 1st Circle (Inner): Red Danger Zone (>= -60 dBm)
    // 2nd Circle (Middle): Yellow Warning Zone (-60 to -74 dBm)
    // 3rd Circle (Outer): Green Safe Zone (< -74 dBm)
    final rRed = maxRadius * 0.35;
    final rYellow = maxRadius * 0.70;
    final rGreen = maxRadius * 1.00;

    // Background Zone Fills
    final redFill = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: isDark ? 0.08 : 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, rRed, redFill);

    final yellowFill = Paint()
      ..color = const Color(0xFFFFD600).withValues(alpha: isDark ? 0.04 : 0.03)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, rYellow, yellowFill);

    final greenFill = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: isDark ? 0.03 : 0.02)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, rGreen, greenFill);

    // Ring Strokes
    final redRingPaint = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: isDark ? 0.6 : 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, rRed, redRingPaint);

    final yellowRingPaint = Paint()
      ..color = const Color(0xFFFFD600).withValues(alpha: isDark ? 0.5 : 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, rYellow, yellowRingPaint);

    final greenRingPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: isDark ? 0.5 : 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, rGreen, greenRingPaint);

    // 3. Crosshairs
    final crossHairPaint = Paint()
      ..color = isDark
          ? const Color(0xFF1E293B).withValues(alpha: 0.8)
          : const Color(0xFFE2E8F0).withValues(alpha: 0.9)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), crossHairPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), crossHairPaint);

    // 4. Rotating Radar Sweep Beam
    final sweepEnd = Offset(
      center.dx + maxRadius * cos(sweepAngle),
      center.dy + maxRadius * sin(sweepAngle),
    );
    final sweepBeamColor = (trackingSource == TrackingSource.directPhone)
        ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
        : (isDark ? const Color(0xFFA855F7) : const Color(0xFF9333EA));

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: sweepAngle - 0.5,
        endAngle: sweepAngle,
        colors: [
          Colors.transparent,
          sweepBeamColor.withValues(alpha: isDark ? 0.25 : 0.18),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, sweepPaint);

    final linePaint = Paint()
      ..color = sweepBeamColor.withValues(alpha: isDark ? 0.5 : 0.4)
      ..strokeWidth = 1.5;
    canvas.drawLine(center, sweepEnd, linePaint);

    // 5. Center Avatar (Phone or Child Wristband)
    final centerColor = (trackingSource == TrackingSource.directPhone)
        ? const Color(0xFF0284C7)
        : const Color(0xFFA855F7);

    final centerGlow = Paint()
      ..color = centerColor.withValues(alpha: isDark ? 0.3 : 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 18 + pulseValue * 6, centerGlow);

    final centerDot = Paint()
      ..color = centerColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, centerDot);

    // Inner bright pip
    final centerInnerDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3, centerInnerDot);

    // 6. Draw Nodes strictly as Red, Yellow, Green dots (NO distance labels on radar)
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      // Dynamic angle distribution for N nodes
      final double angle = (nodes.length == 3)
          ? ([-pi / 2, pi / 6, 5 * pi / 6][i])
          : ((-pi / 2) + (2 * pi * i / nodes.length));

      final isDirect = trackingSource == TrackingSource.directPhone;
      final rssi = isDirect ? (node.directFilteredRssi ?? node.directRawRssi) : node.wbFilteredRssi;
      final state = isDirect ? node.directState : node.wbState;

      final isOnline = state != NodeState.offline && rssi != null && rssi != ShapnestProtocol.rssiOffline;

      // Determine circle ring and dot color strictly based on Red/Yellow/Green zones
      double targetRadius;
      Color dotColor;
      bool isStrongSignal = false;

      if (isOnline) {
        if (rssi >= node.dangerRssiDbm) { // >= -60 dBm (Red Danger Zone)
          targetRadius = rRed;
          dotColor = const Color(0xFFFF1744); // Pure Red Dot
          isStrongSignal = true;
        } else if (rssi >= node.warningRssiDbm) { // -60 dBm to -74 dBm (Yellow Zone)
          targetRadius = rYellow;
          dotColor = const Color(0xFFFFD600); // Pure Yellow Dot
        } else { // < -74 dBm (Green Zone)
          targetRadius = rGreen;
          dotColor = const Color(0xFF00E676); // Pure Green Dot
        }
      } else {
        targetRadius = rGreen;
        dotColor = const Color(0xFF94A3B8); // Muted grey if offline
      }

      final nodePos = Offset(
        center.dx + targetRadius * cos(angle),
        center.dy + targetRadius * sin(angle),
      );

      final isHazardCritical = isOnline && node.isCriticalHazardAlert(rssi);

      // Node Marker Glow
      if (isOnline) {
        final nodeGlow = Paint()
          ..color = dotColor.withValues(alpha: isHazardCritical ? 0.7 : (isStrongSignal ? 0.5 : 0.3))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(nodePos, 14 + (isStrongSignal ? pulseValue * 8 : 0), nodeGlow);
      }

      // Node Marker Core Dot (Pure colored dot)
      final nodeCore = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(nodePos, isOnline ? 9 : 6, nodeCore);

      // White inner dot for sharp contrast
      if (isOnline) {
        final innerDot = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(nodePos, 3, innerDot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return true;
  }
}
