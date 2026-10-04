import 'package:flutter/material.dart';
import '../../services/ble_service.dart';

class CalibrationSheet extends StatefulWidget {
  final BleService bleService;
  final int initialNodeId;

  const CalibrationSheet({
    super.key,
    required this.bleService,
    this.initialNodeId = 1,
  });

  @override
  State<CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<CalibrationSheet> {
  late int _selectedNodeId;
  late double _currentN;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.initialNodeId;
    _currentN = widget.bleService.distanceEngine.globalPathLossN;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: widget.bleService,
      builder: (context, child) {
        final node = widget.bleService.nodes.firstWhere((n) => n.id == _selectedNodeId);
        final calState = widget.bleService.activeCalibration;
        final isCalibratingThisNode = calState != null && calState.nodeId == _selectedNodeId;

        final boxBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
        final boxBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

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

                // Title
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
                            'Accuracy Calibration Wizard',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Eliminates RSSI variance & phone antenna offset',
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
                const SizedBox(height: 20),

                // Node Selection Tabs
                Text(
                  'SELECT ANCHOR NODE TO CALIBRATE',
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
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedNodeId = n.id;
                            });
                          },
                          label: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                n.icon,
                                size: 16,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                n.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                ),
                              ),
                            ],
                          ),
                          selectedColor: n.primaryColor,
                          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          side: BorderSide(
                            color: isSelected
                                ? n.primaryColor
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // 1-Meter Calibration Wizard Box
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
                          Text(
                            'Step 1: 1-Meter Reference RSSI (A)',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'A = ${node.calibratedA} dBm',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Place your phone exactly 1.0 meter away from the node antenna with clear line of sight, then tap Start.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Calibration in progress indicator
                      if (isCalibratingThisNode) ...[
                        if (!calState.isCompleted) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recording live samples... (${calState.collectedRssi.length}/${calState.targetSamples})',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${(calState.progress * 100).toInt()}%',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: calState.progress,
                            backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Calibrated! Reference at 1m set to: ${calState.finalCalibratedA} dBm',
                                    style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],

                      // Calibration Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isCalibratingThisNode && !calState.isCompleted
                                  ? () => widget.bleService.cancelCalibration()
                                  : () => widget.bleService.startCalibration(node.id),
                              icon: Icon(
                                isCalibratingThisNode && !calState.isCompleted ? Icons.cancel : Icons.play_arrow,
                                size: 18,
                              ),
                              label: Text(
                                isCalibratingThisNode && !calState.isCompleted ? 'CANCEL' : 'START 1M CALIBRATION',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCalibratingThisNode && !calState.isCompleted
                                    ? Colors.red.withValues(alpha: 0.8)
                                    : (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7)),
                                foregroundColor: isDark ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
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
                            ),
                            child: const Text('RESET', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Environmental Exponent (n) Section
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
                          Text(
                            'Step 2: Path Loss Exponent (n)',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'n = ${_currentN.toStringAsFixed(1)}',
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
                      const SizedBox(height: 8),
                      Text(
                        'Compensates for wall reflections & room layout absorption.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Presets
                      Row(
                        children: [
                          _buildPresetChip('Free Space', 2.0, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('Living Room', 2.4, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('Obstructed', 3.0, isDark),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFA855F7),
                          inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          thumbColor: const Color(0xFFA855F7),
                          overlayColor: const Color(0xFFA855F7).withValues(alpha: 0.2),
                        ),
                        child: Slider(
                          value: _currentN,
                          min: 1.6,
                          max: 3.6,
                          divisions: 20,
                          label: _currentN.toStringAsFixed(1),
                          onChanged: (val) {
                            setState(() {
                              _currentN = val;
                            });
                            widget.bleService.setGlobalPathLossN(val);
                          },
                        ),
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

  Widget _buildPresetChip(String title, double nValue, bool isDark) {
    final isSelected = (_currentN - nValue).abs() < 0.05;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentN = nValue;
          });
          widget.bleService.setGlobalPathLossN(nValue);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
                      : (isDark ? Colors.white60 : const Color(0xFF475569)),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'n=$nValue',
                style: TextStyle(
                  color: isSelected ? const Color(0xFFA855F7) : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
