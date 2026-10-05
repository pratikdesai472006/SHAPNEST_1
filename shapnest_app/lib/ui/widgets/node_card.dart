import 'package:flutter/material.dart';
import '../../models/node_data.dart';
import '../../models/shapnest_protocol.dart';
import '../../services/ble_service.dart';
import '../../services/distance_engine.dart';
import '../../services/kalman_filter.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
    final zone = isOnline ? node.getZone(distM) : null;
    final isDanger = isOnline && (zone == ProximityZone.criticalDanger || zone == ProximityZone.danger);

    // Dynamic Card Border & Background Colors
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDanger
        ? const Color(0xFFFF1744)
        : (isOnline
            ? (isDark ? node.primaryColor.withValues(alpha: 0.5) : node.primaryColor.withValues(alpha: 0.6))
            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: isDanger ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDanger
                ? const Color(0xFFFF1744).withValues(alpha: 0.25)
                : (isOnline
                    ? node.primaryColor.withValues(alpha: isDark ? 0.12 : 0.08)
                    : (isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.04))),
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
              decoration: BoxDecoration(
                color: zone == ProximityZone.criticalDanger
                    ? const Color(0xFFFF1744)
                    : const Color(0xFFFF9100),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    zone == ProximityZone.criticalDanger
                        ? 'CRITICAL PROXIMITY HAZARD (< 30 cm)!'
                        : 'PROXIMITY DANGER ZONE (30–100 cm)!',
                    style: const TextStyle(
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
                // Top Row: Icon, Name, and State Badges
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: node.primaryColor.withValues(alpha: isDark ? 0.15 : 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: node.primaryColor.withValues(alpha: isDark ? 0.4 : 0.3),
                        ),
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
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
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
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // State Badge
                    _buildStatePill(state, isDark),
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
                          Row(
                            children: [
                              Text(
                                'ESTIMATED DISTANCE',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (isOnline && zone != null) ...[
                                const SizedBox(width: 6),
                                _buildZoneBadge(zone),
                              ],
                            ],
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
                                        color: isDanger
                                            ? const Color(0xFFFF1744)
                                            : theme.colorScheme.onSurface,
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -1.0,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      unit,
                                      style: TextStyle(
                                        color: isDanger ? const Color(0xFFFF1744) : node.primaryColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (distM >= ShapnestProtocol.distanceMaxM) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.15),
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
                              : Text(
                                  '——',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
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
                            _buildSignalBars(rssi, isDark),
                            const SizedBox(width: 8),
                            Text(
                              isOnline && rssi != null ? '$rssi dBm' : '——',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (isOnline && trackingSource == TrackingSource.directPhone)
                              _buildMotionStateIndicator(node.directMotionState, isDark),
                            const SizedBox(width: 4),
                            Text(
                              'Filtered RSSI',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  height: 1,
                ),
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
                          color: node.isUserCalibrated
                              ? Colors.amber
                              : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '1m: ${node.calibratedA} dBm | n: ${node.pathLossExpN.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
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
                        foregroundColor: isDark ? node.primaryColor : const Color(0xFF0284C7),
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

  Widget _buildZoneBadge(ProximityZone zone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: zone.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: zone.color.withValues(alpha: 0.5)),
      ),
      child: Text(
        zone.displayName,
        style: TextStyle(
          color: zone.color,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildMotionStateIndicator(FilterMotionState motionState, bool isDark) {
    Color color;
    String label;
    switch (motionState) {
      case FilterMotionState.stationary:
        color = const Color(0xFF10B981); // Green still
        label = 'STABLE';
        break;
      case FilterMotionState.moving:
        color = const Color(0xFF38BDF8); // Cyan moving
        label = 'TRACKING';
        break;
      case FilterMotionState.fastAttack:
        color = const Color(0xFFFF9100); // Amber fast attack
        label = 'FAST ATTACK';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatePill(NodeState state, bool isDark) {
    Color bg;
    Color fg;
    String label;

    switch (state) {
      case NodeState.active:
        bg = const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.15);
        fg = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
        label = 'ACTIVE';
        break;
      case NodeState.stale:
        bg = const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.15);
        fg = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
        label = 'STALE';
        break;
      case NodeState.offline:
        bg = const Color(0xFF64748B).withValues(alpha: isDark ? 0.2 : 0.15);
        fg = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
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

  Widget _buildSignalBars(int? rssi, bool isDark) {
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

    final inactiveColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

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
            color: isActive ? const Color(0xFF10B981) : inactiveColor,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
