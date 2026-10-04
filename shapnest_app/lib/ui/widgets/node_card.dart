import 'package:flutter/material.dart';
import '../../models/node_data.dart';
import '../../models/shapnest_protocol.dart';
import '../../services/ble_service.dart';

class NodeCard extends StatelessWidget {
  final NodeData node;
  final TrackingSource trackingSource;
  final String unit; // 'm' or 'cm'
  final VoidCallback onCalibrate;

  const NodeCard({
    super.key,
    required this.node,
    required this.trackingSource,
    required this.unit,
    required this.onCalibrate,
  });

  @override
  Widget build(BuildContext context) {
    final distM = (trackingSource == TrackingSource.directPhone)
        ? node.directDistanceM
        : node.wbDistanceM;
    final state = (trackingSource == TrackingSource.directPhone)
        ? node.directState
        : node.wbState;
    final rssi = (trackingSource == TrackingSource.directPhone)
        ? node.directFilteredRssi
        : node.wbFilteredRssi;

    final isOnline = state != NodeState.offline && distM != null;
    final isDanger = isOnline && node.isDanger(distM);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDanger
              ? const Color(0xFFFF5252).withValues(alpha: 0.9)
              : (isOnline ? node.primaryColor.withValues(alpha: 0.5) : const Color(0xFF334155)),
          width: isDanger ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDanger
                ? const Color(0xFFFF5252).withValues(alpha: 0.25)
                : (isOnline ? node.primaryColor.withValues(alpha: 0.12) : Colors.black26),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Danger Alert Ribbon
          if (isDanger)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFF5252),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'PROXIMITY DANGER ZONE WARNING!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Top Row: Icon, Name, and State Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: node.primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: node.primaryColor.withValues(alpha: 0.4)),
                      ),
                      child: Icon(node.icon, color: node.primaryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Node ${node.id} — ${node.name}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trackingSource == TrackingSource.directPhone
                                ? 'Direct Phone Link'
                                : 'Wristband Telemetry Link',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatePill(state),
                  ],
                ),

                const SizedBox(height: 16),

                // Main Distance & RSSI Metric Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Distance Readout
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ESTIMATED DISTANCE',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          isOnline
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      unit == 'm'
                                          ? distM.toStringAsFixed(2)
                                          : (distM * 100).toInt().toString(),
                                      style: TextStyle(
                                        color: isDanger ? const Color(0xFFFF5252) : Colors.white,
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -1.0,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      unit,
                                      style: TextStyle(
                                        color: isDanger ? const Color(0xFFFF5252) : node.primaryColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (distM >= ShapnestProtocol.distanceMaxM) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'CEILING',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : const Text(
                                  '——',
                                  style: TextStyle(
                                    color: Colors.white24,
                                    fontSize: 38,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ],
                      ),
                    ),

                    // Filtered RSSI & Signal Bars
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            _buildSignalBars(rssi),
                            const SizedBox(width: 8),
                            Text(
                              isOnline && rssi != null ? '$rssi dBm' : '——',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Filtered RSSI',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(color: Color(0xFF334155), height: 1),
                const SizedBox(height: 12),

                // Footer Row: Calibration details & Quick Calibrate Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          node.isUserCalibrated ? Icons.verified : Icons.tune,
                          size: 14,
                          color: node.isUserCalibrated ? Colors.amber : Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '1m: ${node.calibratedA} dBm | n: ${node.pathLossExpN.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (node.isUserCalibrated) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'CAL',
                              style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Quick Calibrate Button
                    TextButton.icon(
                      onPressed: onCalibrate,
                      icon: const Icon(Icons.compass_calibration, size: 14),
                      label: const Text('CALIBRATE 1m', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        foregroundColor: node.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatePill(NodeState state) {
    Color bg;
    Color fg;
    String label;

    switch (state) {
      case NodeState.active:
        bg = const Color(0xFF10B981).withValues(alpha: 0.2);
        fg = const Color(0xFF34D399);
        label = 'ACTIVE';
        break;
      case NodeState.stale:
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.2);
        fg = const Color(0xFFFBBF24);
        label = 'STALE';
        break;
      case NodeState.offline:
        bg = const Color(0xFF475569).withValues(alpha: 0.2);
        fg = const Color(0xFF94A3B8);
        label = 'OFFLINE';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBars(int? rssi) {
    int bars = 0;
    if (rssi != null && rssi > -100) {
      if (rssi >= -55) {
        bars = 4;
      } else if (rssi >= -68) {
        bars = 3;
      } else if (rssi >= -80) {
        bars = 2;
      } else {
        bars = 1;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final height = (index + 1) * 4.0;
        final isActive = index < bars;
        return Container(
          width: 3.5,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF10B981) : const Color(0xFF334155),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
