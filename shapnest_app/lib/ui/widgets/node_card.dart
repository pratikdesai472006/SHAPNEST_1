import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/node_data.dart';
import '../../models/shapnest_protocol.dart';
import '../../services/ble_service.dart';
import '../../services/distance_engine.dart';

class NodeCard extends StatelessWidget {
  final NodeData node;
  final TrackingSource trackingSource;
  final String unit; // 'm' or 'cm'
  final VoidCallback onCalibrate;
  final VoidCallback? onRename;
  final VoidCallback? onToggleFan;

  const NodeCard({
    super.key,
    required this.node,
    required this.trackingSource,
    required this.unit,
    required this.onCalibrate,
    this.onRename,
    this.onToggleFan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isDirect = trackingSource == TrackingSource.directPhone;
    final distM = isDirect ? node.directDistanceM : node.wbDistanceM;
    final state = isDirect ? node.directState : node.wbState;
    final rssi = isDirect ? (node.directFilteredRssi ?? node.directRawRssi) : node.wbFilteredRssi;

    final isOnline = state != NodeState.offline && rssi != null && rssi != ShapnestProtocol.rssiOffline;
    final signalZone = (isOnline) ? node.getSignalZone(rssi) : null;

    // Safety Alert States: Red Zone proximity alone triggers urgent alert & loud alarm
    final isCriticalAlert = isOnline && (signalZone == ProximityZone.danger);
    final isWarningAlert = isOnline && (signalZone == ProximityZone.warning);

    // Dynamic Card Border & Background Colors
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isCriticalAlert
        ? const Color(0xFFFF1744)
        : (isWarningAlert
            ? const Color(0xFFFFD600)
            : (isOnline
                ? (isDark ? node.primaryColor.withValues(alpha: 0.5) : node.primaryColor.withValues(alpha: 0.6))
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: isCriticalAlert ? 2.0 : (isWarningAlert ? 1.5 : 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: isCriticalAlert
                ? const Color(0xFFFF1744).withValues(alpha: 0.25)
                : (isWarningAlert
                    ? const Color(0xFFFFD600).withValues(alpha: 0.20)
                    : (isOnline
                        ? node.primaryColor.withValues(alpha: isDark ? 0.12 : 0.08)
                        : (isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.04)))),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Critical Red Danger Alert Ribbon (Child Very Near Node)
          if (isCriticalAlert)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFF1744),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'URGENT: Your child is very near the ${node.name.toLowerCase()}!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),

          // 2. Yellow Caution Warning Ribbon
          if (isWarningAlert)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFD600),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.black, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'WARNING: Your child is near the ${node.name.toLowerCase()}.',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Top Row: Icon, Name (with Rename button), and State Badges (Wrap to prevent overflow)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Node ${node.id} — ${node.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (onRename != null) ...[
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: onRename,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2.0),
                                    child: Icon(
                                      Icons.edit_outlined,
                                      size: 14,
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isDirect ? 'Phone Direct BLE Link' : 'Child Wristband Safety Link',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // State & Sensor Badges wrapped safely
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildStatePill(state, isDark),
                        if (node.id == 1 && state != NodeState.offline)
                          _buildFanHeaderPill(node.isFanOn, isDark),
                        if (node.id == 2 && state != NodeState.offline)
                          _buildIronHeaderPill(node.ironTemperatureC, isDark),
                        if (node.id == 3 && state != NodeState.offline)
                          _buildDoorHeaderPill(node.doorState, isDark),
                      ],
                    ),
                  ],
                ),

                // Fan Status Banner (Node 1 only)
                if (node.id == 1) ...[
                  const SizedBox(height: 12),
                  _buildFanBanner(node.isFanOn, isDark, theme, onToggleFan),
                ],

                // Iron Temperature Live Status (Node 2 only)
                if (node.id == 2) ...[
                  const SizedBox(height: 12),
                  _buildIronTemperatureBanner(
                    state == NodeState.offline ? null : node.ironTemperatureC,
                    isDark,
                    theme,
                  ),
                ],

                // Door Reed Switch Live Status (Node 3 only)
                if (node.id == 3) ...[
                  const SizedBox(height: 12),
                  _buildDoorSensorBanner(
                    state == NodeState.offline ? DoorState.unknown : node.doorState,
                    isDark,
                    theme,
                  ),
                ],

                const SizedBox(height: 16),

                // Main Signal Strength & Estimated Distance Metric Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Signal Strength (RSSI) Primary Readout
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'SIGNAL STRENGTH (RSSI)',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (isOnline && signalZone != null) ...[
                                const SizedBox(width: 6),
                                _buildZoneBadge(signalZone),
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
                                      '$rssi',
                                      style: TextStyle(
                                        color: isCriticalAlert
                                            ? const Color(0xFFFF1744)
                                            : (isWarningAlert
                                                ? const Color(0xFFFFD600)
                                                : theme.colorScheme.onSurface),
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -1.0,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'dBm',
                                      style: TextStyle(
                                        color: isCriticalAlert
                                            ? const Color(0xFFFF1744)
                                            : node.primaryColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
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

                    // Signal Quality & Proximity Level Readout (Safe / Near / Very Near)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSignalBars(rssi, isDark),
                            const SizedBox(width: 8),
                            Text(
                              isOnline
                                  ? node.getProximityLabel(rssi)
                                  : 'Offline',
                              style: TextStyle(
                                color: isCriticalAlert
                                    ? const Color(0xFFFF1744)
                                    : (isWarningAlert
                                        ? const Color(0xFFFFD600)
                                        : (isOnline ? const Color(0xFF00E676) : theme.colorScheme.onSurfaceVariant)),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Proximity Level',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Manual Red / Yellow / Green Safety Zone Spectrum Bar for this node
                _buildManualZoneBar(node, rssi, distM, unit, isDark),

                const SizedBox(height: 12),
                Divider(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  height: 1,
                ),
                const SizedBox(height: 12),

                // Footer Row: Calibration details & Quick Calibrate Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            node.isUserCalibrated ? Icons.verified : Icons.tune,
                            size: 14,
                            color: node.isUserCalibrated
                                ? Colors.amber
                                : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '1m: ${node.wbCalibratedA} dBm | n: ${node.pathLossExpN.toStringAsFixed(1)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
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
                    ),
                    const SizedBox(width: 8),

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

  Widget _buildFanHeaderPill(bool isFanOn, bool isDark) {
    final color = isFanOn ? const Color(0xFFFF1744) : const Color(0xFF10B981);
    final text = isFanOn ? 'FAN ON (ACTIVE)' : 'FAN OFF (SAFE)';
    final icon = isFanOn ? Icons.cyclone_rounded : Icons.shield_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.6 : 0.5),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoorHeaderPill(DoorState doorState, bool isDark) {
    final isOpen = doorState == DoorState.open;
    final isUnknown = doorState == DoorState.unknown;
    final color = isUnknown
        ? const Color(0xFF94A3B8)
        : (isOpen ? const Color(0xFFFF3D00) : const Color(0xFF10B981));
    final text = isUnknown ? 'STATUS ?' : (isOpen ? 'DOOR OPEN' : 'DOOR CLOSED');
    final icon = isUnknown
        ? Icons.help_outline_rounded
        : (isOpen ? Icons.meeting_room_outlined : Icons.lock_outline_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.6 : 0.5),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoorSensorBanner(DoorState doorState, bool isDark, ThemeData theme) {
    final isOpen = doorState == DoorState.open;
    final isUnknown = doorState == DoorState.unknown;

    final color = isUnknown
        ? const Color(0xFF94A3B8)
        : (isOpen ? const Color(0xFFFF3D00) : const Color(0xFF10B981));

    final icon = isUnknown
        ? Icons.help_outline_rounded
        : (isOpen ? Icons.meeting_room_outlined : Icons.door_front_door_outlined);

    final title = isUnknown
        ? 'DOOR STATUS UNKNOWN'
        : (isOpen ? 'DOOR IS OPEN' : 'DOOR IS CLOSED');

    final subtext = isUnknown
        ? 'Awaiting BLE telemetry...'
        : (isOpen ? 'Magnetic Reed Contact Separated' : 'Magnetic Contact Securely Closed');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.5 : 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  subtext,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isOpen ? 'OPEN' : (isUnknown ? 'WAIT' : 'CLOSED'),
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFanBanner(bool isFanOn, bool isDark, ThemeData theme, VoidCallback? onToggle) {
    final color = isFanOn ? const Color(0xFFFF1744) : const Color(0xFF10B981);
    final icon = isFanOn ? Icons.cyclone_rounded : Icons.shield_rounded;
    final title = isFanOn ? 'FAN IS SPINNING (BLADES ACTIVE)' : 'FAN IS POWERED OFF (SAFE)';
    final subtext = isFanOn
        ? 'Hazard condition fulfilled: Child proximity alert active'
        : 'Blades stopped: Child near is safe, alarms silenced';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.5 : 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  subtext,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          if (onToggle != null)
            GestureDetector(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  isFanOn ? 'TURN OFF' : 'TURN ON',
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIronHeaderPill(int? tempC, bool isDark) {
    final isUnknown = tempC == null;
    final isHot = !isUnknown && tempC >= ShapnestProtocol.ironHotThresholdC;
    final isWarm = !isUnknown && tempC >= ShapnestProtocol.ironWarmThresholdC && !isHot;

    final color = isUnknown
        ? const Color(0xFF94A3B8)
        : (isHot
            ? const Color(0xFFFF1744)
            : (isWarm ? const Color(0xFFFF9100) : const Color(0xFF10B981)));
    final text = isUnknown
        ? 'TEMP ?'
        : (isHot ? '$tempC°C HOT' : (isWarm ? '$tempC°C WARM' : '$tempC°C SAFE'));
    final icon = isUnknown
        ? Icons.help_outline_rounded
        : (isHot
            ? Icons.local_fire_department_rounded
            : (isWarm ? Icons.whatshot_outlined : Icons.thermostat_rounded));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.6 : 0.5),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIronTemperatureBanner(int? tempC, bool isDark, ThemeData theme) {
    final isUnknown = tempC == null;
    final isHot = !isUnknown && tempC >= ShapnestProtocol.ironHotThresholdC;
    final isWarm = !isUnknown && tempC >= ShapnestProtocol.ironWarmThresholdC && !isHot;

    final color = isUnknown
        ? const Color(0xFF94A3B8)
        : (isHot
            ? const Color(0xFFFF1744)
            : (isWarm ? const Color(0xFFFF9100) : const Color(0xFF10B981)));

    final icon = isUnknown
        ? Icons.help_outline_rounded
        : (isHot
            ? Icons.local_fire_department_rounded
            : (isWarm ? Icons.whatshot_outlined : Icons.check_circle_outline_rounded));

    final title = isUnknown
        ? 'TEMPERATURE UNKNOWN'
        : (isHot
            ? 'IRON IS DANGEROUSLY HOT ($tempC°C)'
            : (isWarm
                ? 'IRON IS WARM ($tempC°C)'
                : 'IRON IS AT SAFE TEMPERATURE ($tempC°C)'));

    final subtext = isUnknown
        ? 'Awaiting BLE temperature telemetry...'
        : (isHot
            ? 'High burn hazard! Keep children away'
            : (isWarm
                ? 'Surface is cooling or warming up'
                : 'Safe to touch / Ambient temperature'));

    final badgeText = isUnknown
        ? 'WAIT'
        : (isHot ? 'HOT' : (isWarm ? 'WARM' : 'SAFE'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.5 : 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  subtext,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualZoneBar(NodeData node, int? rssi, double? distM, String unit, bool isDark) {
    final dangerRssi = node.dangerRssiDbm; // default -60 dBm
    final warnRssi = node.warningRssiDbm;   // default -74 dBm
    const minScale = -100.0; // weak / far
    const maxScale = -20.0;  // strong / very close

    final safeFlex = max(1, ((warnRssi - minScale).clamp(5, 50)).toInt());
    final warnFlex = max(1, ((dangerRssi - warnRssi).clamp(5, 40)).toInt());
    final dangerFlex = max(1, ((maxScale - dangerRssi).clamp(5, 40)).toInt());

    // Indicator position fraction (0.0 to 1.0)
    final progress = (rssi != null)
        ? (((rssi.toDouble() - minScale) / (maxScale - minScale)).clamp(0.02, 0.98))
        : null;

    final dangerText = '≥ $dangerRssi dBm';
    final warnText = '$warnRssi to $dangerRssi dBm';
    final safeText = '< $warnRssi dBm';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SIGNAL STRENGTH SPECTRUM',
              style: TextStyle(
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              rssi != null
                  ? '$rssi dBm • ${node.getProximityLabel(rssi)}'
                  : '——',
              style: TextStyle(
                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Visual Tri-Zone Gauge with Current Position Cursor
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final maxCursorX = max(0.0, barWidth - 10);
            final double xPos = (progress != null)
                ? (barWidth * progress).clamp(0.0, maxCursorX).toDouble()
                : 0.0;
            return SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  // Tri-color bar (Green -> Yellow -> Red)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 8,
                        child: Row(
                          children: [
                            Expanded(flex: safeFlex, child: Container(color: const Color(0xFF00E676))),
                            Expanded(flex: warnFlex, child: Container(color: const Color(0xFFFFD600))),
                            Expanded(flex: dangerFlex, child: Container(color: const Color(0xFFFF1744))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Current Signal Cursor Pin
                  if (progress != null)
                    Positioned(
                      left: xPos,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.black, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 5),

        // Responsive Multi-Zone Legend
        Row(
          children: [
            Expanded(
              child: Text(
                '🟢 Safe ($safeText)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '🟡 Warn ($warnText)',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? const Color(0xFFFFD600) : const Color(0xFFB45309),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '🔴 Danger ($dangerText)',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFF1744),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
