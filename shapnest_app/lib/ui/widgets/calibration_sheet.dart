import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/ble_service.dart';
import '../../services/distance_engine.dart';
import '../../services/theme_service.dart';

class CalibrationSheet extends StatefulWidget {
  final BleService bleService;
  final ThemeService? themeService;
  final int initialNodeId;
  final String currentUnit;
  final ValueChanged<String>? onUnitChanged;

  const CalibrationSheet({
    super.key,
    required this.bleService,
    this.themeService,
    this.initialNodeId = 1,
    this.currentUnit = 'm',
    this.onUnitChanged,
  });

  @override
  State<CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<CalibrationSheet> {
  late int _selectedNodeId;
  late String _activeUnit;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.initialNodeId;
    _activeUnit = widget.currentUnit;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: widget.bleService,
      builder: (context, child) {
        final node = widget.bleService.nodes.firstWhere(
          (n) => n.id == _selectedNodeId,
          orElse: () => widget.bleService.nodes.first,
        );
        final calState = widget.bleService.activeCalibration;
        final isCalibratingThisNode = calState != null && calState.nodeId == _selectedNodeId;

        final boxBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
        final boxBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final currentN = node.pathLossExpN;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header with Title & Close
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.tune,
                        color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calibration & Zones',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Fine-tune wristband accuracy & safety boundaries',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ==========================================================
                // APP PREFERENCES: UNITS (m / cm) & THEME MODE
                // ==========================================================
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: boxBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: boxBorder),
                  ),
                  child: Row(
                    children: [
                      // Unit selector
                      Text(
                        'Units:',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            _buildUnitTab('m', isDark),
                            _buildUnitTab('cm', isDark),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Theme Selector (Dark & Light only)
                      if (widget.themeService != null) ...[
                        Text(
                          'Theme:',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildThemeButton(ThemeMode.dark, Icons.dark_mode, isDark),
                        const SizedBox(width: 6),
                        _buildThemeButton(ThemeMode.light, Icons.light_mode, isDark),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ==========================================================
                // SELECT ANCHOR NODE TABS (Responsive Wrap - Never Overflows)
                // ==========================================================
                Text(
                  'SELECT ANCHOR NODE',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: widget.bleService.nodes.map((n) {
                    final isSelected = n.id == _selectedNodeId;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedNodeId = n.id;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? n.primaryColor.withValues(alpha: isDark ? 0.30 : 0.18)
                                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? n.primaryColor
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  n.icon,
                                  size: 16,
                                  color: isSelected
                                      ? n.primaryColor
                                      : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  n.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                        : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 18),

                // ==========================================================
                // STEP 1: 1-METER REFERENCE RSSI (A) — Clean Stacked Layout
                // ==========================================================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: boxBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: boxBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Step 1: 1m Reference RSSI (A)',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Nudge controls in their own compact row
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                tooltip: 'Nudge A -1 dBm',
                                color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                onPressed: () => widget.bleService.nudgeCalibration(node.id, -1),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'A = ${node.wbCalibratedA} dBm',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                tooltip: 'Nudge A +1 dBm',
                                color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                onPressed: () => widget.bleService.nudgeCalibration(node.id, 1),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hold the wristband 1.0m from Node ${node.id} (${node.name}). Tap Start to record or use [–]/[+] to adjust.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Calibration progress
                      if (isCalibratingThisNode) ...[
                        if (!calState.isCompleted) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recording samples... (${calState.collectedRssi.length}/${calState.targetSamples})',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${(calState.progress * 100).toInt()}%',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: calState.progress,
                            backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Calibrated! Reference at 1m set to: ${calState.finalCalibratedA} dBm',
                                    style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isCalibratingThisNode && !calState.isCompleted
                                  ? () => widget.bleService.cancelCalibration()
                                  : () => widget.bleService.startCalibration(node.id),
                              icon: Icon(
                                isCalibratingThisNode && !calState.isCompleted ? Icons.cancel : Icons.play_arrow,
                                size: 16,
                              ),
                              label: Text(
                                isCalibratingThisNode && !calState.isCompleted ? 'CANCEL' : 'START 1M AUTO-CALIBRATION',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCalibratingThisNode && !calState.isCompleted
                                    ? Colors.red.withValues(alpha: 0.8)
                                    : (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7)),
                                foregroundColor: isDark ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => widget.bleService.resetNodeCalibration(node.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurfaceVariant,
                              side: BorderSide(
                                color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            child: const Text('RESET', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ==========================================================
                // STEP 2: PATH LOSS EXPONENT (n) FOR THIS NODE
                // ==========================================================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: boxBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: boxBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Step 2: Path Loss Exponent for ${node.name} (n)',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'n = ${currentN.toStringAsFixed(1)}',
                              style: const TextStyle(
                                color: Color(0xFFA855F7),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Configured individually for Node ${node.id} to account for local walls & room absorption.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Presets (Never overflows)
                      Row(
                        children: [
                          _buildPresetChip('Free Space', DistanceEngine.getDefaultFreeSpaceN(node.id), currentN, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('Living Room', 2.5, currentN, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('Obstructed', 3.0, currentN, isDark),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFA855F7),
                          inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          thumbColor: const Color(0xFFA855F7),
                          overlayColor: const Color(0xFFA855F7).withValues(alpha: 0.2),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: currentN.clamp(1.6, 3.6),
                          min: 1.6,
                          max: 3.6,
                          divisions: 20,
                          label: currentN.toStringAsFixed(1),
                          onChanged: (val) {
                            widget.bleService.setNodePathLossN(_selectedNodeId, val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ==========================================================
                // STEP 3: SIGNAL STRENGTH SAFETY ZONES (RED / YELLOW / GREEN)
                // ==========================================================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: boxBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: boxBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Step 3: Signal Zones for ${node.name}',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF1744).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'dBm Thresholds',
                              style: TextStyle(
                                color: Color(0xFFFF1744),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Red Danger (≥ ${node.dangerRssiDbm} dBm) & Yellow Warn (${node.warningRssiDbm} to ${node.dangerRssiDbm} dBm). Mobile message, alarm & vibration trigger only when hazard condition is fulfilled.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Visual Multi-Zone Preview Bar (Green -> Yellow -> Red)
                      () {
                        const minScale = -95.0;
                        const maxScale = -20.0;
                        final warnVal = node.warningRssiDbm.toDouble().clamp(minScale, maxScale - 2.0);
                        final dangerVal = node.dangerRssiDbm.toDouble().clamp(warnVal + 2.0, maxScale);

                        final safeFlex = max(1, ((warnVal - minScale)).round()).toInt();
                        final warnFlex = max(1, ((dangerVal - warnVal)).round()).toInt();
                        final dangerFlex = max(1, ((maxScale - dangerVal)).round()).toInt();

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 12,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: safeFlex,
                                  child: Container(color: const Color(0xFF00E676)),
                                ),
                                Expanded(
                                  flex: warnFlex,
                                  child: Container(color: const Color(0xFFFFD600)),
                                ),
                                Expanded(
                                  flex: dangerFlex,
                                  child: Container(color: const Color(0xFFFF1744)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }(),
                      const SizedBox(height: 8),

                      // Interactive Zone Selection Bar in dBm (-95 to -20 dBm)
                      () {
                        const minScale = -95.0;
                        const maxScale = -20.0;
                        final warnVal = node.warningRssiDbm.toDouble().clamp(minScale, maxScale - 2.0);
                        final dangerVal = max(warnVal + 2.0, node.dangerRssiDbm.toDouble()).clamp(warnVal + 2.0, maxScale);

                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFFFFD600),
                            inactiveTrackColor: const Color(0xFF00E676),
                            thumbColor: isDark ? Colors.white : const Color(0xFF0F172A),
                            rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                            trackHeight: 6,
                          ),
                          child: RangeSlider(
                            values: RangeValues(warnVal, dangerVal),
                            min: minScale,
                            max: maxScale,
                            divisions: 75,
                            labels: RangeLabels(
                              'Warn: ${node.warningRssiDbm} dBm',
                              'Danger: ${node.dangerRssiDbm} dBm',
                            ),
                            onChanged: (RangeValues values) {
                              if (values.start < values.end) {
                                widget.bleService.setNodeWarningRssi(node.id, values.start.round());
                                widget.bleService.setNodeDangerRssi(node.id, values.end.round());
                              }
                            },
                          ),
                        );
                      }(),
                      const SizedBox(height: 8),

                      // Manual Fine-Tune Adjusters Row
                      Row(
                        children: [
                          // Yellow Warning Nudge
                          Expanded(
                            child: _buildRssiZoneNudgeControl(
                              label: '🟡 Yellow Warn',
                              valueDbm: node.warningRssiDbm,
                              color: const Color(0xFFFFD600),
                              isDark: isDark,
                              onMinus: () {
                                final newVal = (node.warningRssiDbm - 1).clamp(-95, node.dangerRssiDbm - 2);
                                widget.bleService.setNodeWarningRssi(node.id, newVal);
                              },
                              onPlus: () {
                                final newVal = (node.warningRssiDbm + 1).clamp(-95, node.dangerRssiDbm - 2);
                                widget.bleService.setNodeWarningRssi(node.id, newVal);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Red Danger Nudge
                          Expanded(
                            child: _buildRssiZoneNudgeControl(
                              label: '🔴 Red Danger',
                              valueDbm: node.dangerRssiDbm,
                              color: const Color(0xFFFF1744),
                              isDark: isDark,
                              onMinus: () {
                                final newVal = (node.dangerRssiDbm - 1).clamp(node.warningRssiDbm + 2, -20);
                                widget.bleService.setNodeDangerRssi(node.id, newVal);
                              },
                              onPlus: () {
                                final newVal = (node.dangerRssiDbm + 1).clamp(node.warningRssiDbm + 2, -20);
                                widget.bleService.setNodeDangerRssi(node.id, newVal);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnitTab(String unit, bool isDark) {
    final isSelected = _activeUnit == unit;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeUnit = unit;
        });
        widget.onUnitChanged?.call(unit);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          unit,
          style: TextStyle(
            color: isSelected
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? Colors.white60 : const Color(0xFF64748B)),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildThemeButton(ThemeMode mode, IconData icon, bool isDark) {
    final isSelected = widget.themeService?.themeMode == mode;
    return InkWell(
      onTap: () => widget.themeService?.setThemeMode(mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF00E5FF).withValues(alpha: 0.25) : const Color(0xFF0284C7).withValues(alpha: 0.2))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
                : Colors.transparent,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected
              ? (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
              : (isDark ? Colors.white60 : const Color(0xFF64748B)),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String title, double nValue, double currentN, bool isDark) {
    final isSelected = (currentN - nValue).abs() < 0.05;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.bleService.setNodePathLossN(_selectedNodeId, nValue);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFA855F7).withValues(alpha: isDark ? 0.25 : 0.20)
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFA855F7)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF6B21A8))
                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'n=${nValue.toStringAsFixed(1)}',
                style: TextStyle(
                  color: isSelected
                      ? (isDark ? const Color(0xFFA855F7) : const Color(0xFF7E22CE))
                      : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRssiZoneNudgeControl({
    required String label,
    required int valueDbm,
    required Color color,
    required bool isDark,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onMinus,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.remove, size: 16, color: color),
                ),
              ),
              Text(
                '$valueDbm dBm',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
              InkWell(
                onTap: onPlus,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.add, size: 16, color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
