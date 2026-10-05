import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/theme_service.dart';
import 'widgets/calibration_sheet.dart';
import 'widgets/diagnostic_sheet.dart';
import 'widgets/node_card.dart';
import 'widgets/radar_view.dart';

class HomeScreen extends StatefulWidget {
  final BleService bleService;
  final ThemeService themeService;

  const HomeScreen({
    super.key,
    required this.bleService,
    required this.themeService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _unit = 'm'; // 'm' or 'cm'

  void _openCalibration([int nodeId = 1]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CalibrationSheet(
        bleService: widget.bleService,
        initialNodeId: nodeId,
      ),
    );
  }

  void _openDiagnostics() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: DiagnosticSheet(bleService: widget.bleService),
      ),
    );
  }

  void _showThemeSelector() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.light_mode_rounded),
                  title: const Text('Light Mode'),
                  trailing: widget.themeService.themeMode == ThemeMode.light
                      ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                      : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    widget.themeService.setThemeMode(ThemeMode.light);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_rounded),
                  title: const Text('Dark Mode'),
                  trailing: widget.themeService.themeMode == ThemeMode.dark
                      ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                      : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    widget.themeService.setThemeMode(ThemeMode.dark);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.brightness_auto_rounded),
                  title: const Text('System Default'),
                  trailing: widget.themeService.themeMode == ThemeMode.system
                      ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                      : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    widget.themeService.setThemeMode(ThemeMode.system);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: widget.bleService,
      builder: (context, child) {
        final ble = widget.bleService;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.appBarTheme.backgroundColor,
            foregroundColor: theme.appBarTheme.foregroundColor,
            elevation: theme.appBarTheme.elevation,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF3B82F6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.radar, color: Colors.black, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SHAPNEST',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Direct BLE Precision Tracker',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              // Theme Selector Toggle
              IconButton(
                icon: Icon(
                  widget.themeService.themeIcon,
                  color: isDark ? const Color(0xFFFFD54F) : const Color(0xFF475569),
                ),
                tooltip: 'Theme: ${widget.themeService.themeName}',
                onPressed: _showThemeSelector,
              ),

              // Dynamic Unit Toggle ('m' <-> 'cm')
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUnitButton('m', isDark),
                    _buildUnitButton('cm', isDark),
                  ],
                ),
              ),
              const SizedBox(width: 4),

              // Simulation / Demo Mode Toggle
              IconButton(
                icon: Icon(
                  ble.isSimulating ? Icons.smart_toy : Icons.smart_toy_outlined,
                  color: ble.isSimulating
                      ? const Color(0xFFA855F7)
                      : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                ),
                tooltip: ble.isSimulating ? 'Stop Demo Simulation' : 'Start Demo Simulation',
                onPressed: () => ble.toggleSimulation(),
              ),

              // Calibration Modal Button
              IconButton(
                icon: Icon(
                  Icons.tune,
                  color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                ),
                tooltip: 'Calibrate Distance Accuracy',
                onPressed: () => _openCalibration(1),
              ),

              // Diagnostic Log Modal Button
              IconButton(
                icon: Icon(
                  Icons.terminal,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
                tooltip: 'Diagnostic Logs',
                onPressed: _openDiagnostics,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              // Simulation Active Warning Banner
              if (ble.isSimulating)
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.science, color: Color(0xFFA855F7), size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          '[DEMO / SIMULATION MODE — SYNTHETIC WALKING DATA]',
                          style: TextStyle(
                            color: Color(0xFFA855F7),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => ble.stopSimulation(),
                          child: Text(
                            'EXIT',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Mode Selection Segmented Control
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildModeTab(
                          title: 'Direct Phone Tracking',
                          subtitle: 'Phone ⟷ Nodes',
                          icon: Icons.smartphone,
                          isSelected: ble.trackingSource == TrackingSource.directPhone,
                          activeColor: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                          isDark: isDark,
                          onTap: () => ble.setTrackingSource(TrackingSource.directPhone),
                        ),
                        const SizedBox(width: 4),
                        _buildModeTab(
                          title: 'Child Wristband',
                          subtitle: ble.isWristbandOnline
                              ? 'Online (Seq #${ble.wristbandSequence})'
                              : 'Offline',
                          icon: Icons.watch,
                          isSelected: ble.trackingSource == TrackingSource.wristband,
                          activeColor: const Color(0xFFA855F7),
                          isDark: isDark,
                          onTap: () => ble.setTrackingSource(TrackingSource.wristband),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Status Ribbon
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ble.isScanning
                              ? const Color(0xFF10B981)
                              : (ble.isSimulating
                                  ? const Color(0xFFA855F7)
                                  : const Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ble.statusMessage,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Path Loss: n=${ble.distanceEngine.globalPathLossN.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Multi-Ring 2.4GHz Radar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: RadarView(
                    nodes: ble.nodes,
                    trackingSource: ble.trackingSource,
                    unit: _unit,
                  ),
                ),
              ),

              // Node Telemetry Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ANCHOR NODES TELEMETRY',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '${ble.nodes.where((n) => (ble.trackingSource == TrackingSource.directPhone ? n.directDistanceM : n.wbDistanceM) != null).length}/3 ACTIVE',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Node Cards List
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final node = ble.nodes[index];
                    return NodeCard(
                      node: node,
                      trackingSource: ble.trackingSource,
                      unit: _unit,
                      onCalibrate: () => _openCalibration(node.id),
                    );
                  },
                  childCount: ble.nodes.length,
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            width: double.infinity,
            child: FloatingActionButton.extended(
              onPressed: () => ble.toggleScan(),
              backgroundColor: ble.isScanning
                  ? const Color(0xFFFF5252)
                  : (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7)),
              foregroundColor: ble.isScanning
                  ? Colors.white
                  : (isDark ? Colors.black : Colors.white),
              elevation: 4,
              icon: Icon(ble.isScanning ? Icons.stop : Icons.bluetooth_searching, size: 22),
              label: Text(
                ble.isScanning ? 'STOP BLE SCAN' : 'START CONTINUOUS BLE SCAN',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnitButton(String unit, bool isDark) {
    final isSelected = _unit == unit;
    final activeColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7);
    final activeTextColor = isDark ? Colors.black : Colors.white;

    return GestureDetector(
      onTap: () {
        setState(() {
          _unit = unit;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          unit,
          style: TextStyle(
            color: isSelected
                ? activeTextColor
                : (isDark ? Colors.white60 : const Color(0xFF64748B)),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: isDark ? 0.15 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: isDark ? 0.5 : 0.4)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? activeColor
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                            : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected
                            ? activeColor
                            : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
