import 'package:flutter/material.dart';
import '../models/node_data.dart';
import '../models/shapnest_protocol.dart';
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

  @override
  void initState() {
    super.initState();
    // Auto-start continuous BLE scan on app open (no user intervention required)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.bleService.isScanning) {
        widget.bleService.startScan();
      }
    });
  }

  void _openCalibration([int nodeId = 1]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CalibrationSheet(
        bleService: widget.bleService,
        themeService: widget.themeService,
        initialNodeId: nodeId,
        currentUnit: _unit,
        onUnitChanged: (newUnit) => setState(() => _unit = newUnit),
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
            titleSpacing: 12,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF3B82F6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.radar, color: Colors.black, size: 18),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SHAPNEST',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        'Precision Tracker',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Setup & Signal Strength Help Guide Button
              IconButton(
                icon: Icon(
                  Icons.help_outline_rounded,
                  color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                ),
                tooltip: 'Help & Signal Guide',
                onPressed: () => _showHelpGuide(context),
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

              // Overflow Menu (Theme, Simulation, Diagnostic Logs)
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
                tooltip: 'More Options',
                onSelected: (value) {
                  switch (value) {
                    case 'theme':
                      _showThemeSelector();
                      break;
                    case 'sim':
                      ble.toggleSimulation();
                      break;
                    case 'logs':
                      _openDiagnostics();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'theme',
                    child: Row(
                      children: [
                        Icon(widget.themeService.themeIcon, size: 18),
                        const SizedBox(width: 10),
                        Text('Theme: ${widget.themeService.themeName}'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sim',
                    child: Row(
                      children: [
                        Icon(
                          ble.isSimulating ? Icons.smart_toy : Icons.smart_toy_outlined,
                          color: ble.isSimulating ? const Color(0xFFA855F7) : null,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(ble.isSimulating ? 'Stop Demo Mode' : 'Start Demo Mode'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'logs',
                    child: Row(
                      children: [
                        Icon(Icons.terminal, size: 18),
                        const SizedBox(width: 10),
                        Text('Diagnostic Logs'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              // Real-Time Safety Zone Alert Banner (Yellow: 1 min, Red: 15s)
              ListenableBuilder(
                listenable: ble.alertService,
                builder: (context, _) {
                  final activeAlert = ble.alertService.currentActiveAlert;
                  if (activeAlert == null) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }

                  final isRed = activeAlert.isDanger;
                  final isYellow = activeAlert.isWarning;
                  final bannerBg = isRed
                      ? const Color(0xFFFF1744).withValues(alpha: isDark ? 0.25 : 0.18)
                      : (isYellow
                          ? const Color(0xFFFFD600).withValues(alpha: isDark ? 0.25 : 0.20)
                          : const Color(0xFF00E676).withValues(alpha: isDark ? 0.25 : 0.18));
                  final bannerBorder = isRed
                      ? const Color(0xFFFF1744)
                      : (isYellow ? const Color(0xFFFFD600) : const Color(0xFF00E676));
                  final bannerText = isRed
                      ? (isDark ? Colors.white : const Color(0xFFB71C1C))
                      : (isYellow
                          ? (isDark ? Colors.white : const Color(0xFF78350F))
                          : (isDark ? Colors.white : const Color(0xFF065F46)));

                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: bannerBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: bannerBorder, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: bannerBorder.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isRed ? '🚨' : (isYellow ? '⚠️' : '✅'),
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    activeAlert.title,
                                    style: TextStyle(
                                      color: bannerText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    activeAlert.body,
                                    style: TextStyle(
                                      color: bannerText.withValues(alpha: 0.9),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 18, color: bannerText),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => ble.alertService.dismissActiveAlert(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

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
                        const Expanded(
                          child: Text(
                            '[DEMO / SIMULATION MODE — SYNTHETIC WALKING DATA]',
                            style: TextStyle(
                              color: Color(0xFFA855F7),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
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

              // Tracking Source Selector (Child Wristband vs Phone's Bluetooth)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildTrackingSourceTab(
                          title: 'Child Wristband',
                          subtitle: ble.isWristbandOnline ? 'Online' : 'Searching',
                          icon: Icons.watch_outlined,
                          isSelected: ble.trackingSource == TrackingSource.wristband,
                          activeColor: const Color(0xFFA855F7),
                          isDark: isDark,
                          onTap: () => ble.setTrackingSource(TrackingSource.wristband),
                        ),
                        const SizedBox(width: 4),
                        _buildTrackingSourceTab(
                          title: "Phone's Bluetooth",
                          subtitle: ble.isScanning ? 'Direct Scanner' : 'Offline',
                          icon: Icons.phone_android_rounded,
                          isSelected: ble.trackingSource == TrackingSource.directPhone,
                          activeColor: const Color(0xFF0284C7),
                          isDark: isDark,
                          onTap: () => ble.setTrackingSource(TrackingSource.directPhone),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Active Tracking Mode Status Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (ble.trackingSource == TrackingSource.directPhone)
                            ? (isDark ? const Color(0xFF0284C7).withValues(alpha: 0.5) : const Color(0xFF38BDF8))
                            : (ble.isWristbandOnline
                                ? const Color(0xFFA855F7).withValues(alpha: 0.5)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (ble.trackingSource == TrackingSource.directPhone)
                              ? const Color(0xFF0284C7).withValues(alpha: 0.10)
                              : (ble.isWristbandOnline
                                  ? const Color(0xFFA855F7).withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: isDark ? 0.1 : 0.03)),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (ble.trackingSource == TrackingSource.directPhone
                                    ? const Color(0xFF0284C7)
                                    : const Color(0xFFA855F7))
                                .withValues(alpha: isDark ? 0.20 : 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            ble.trackingSource == TrackingSource.directPhone
                                ? Icons.bluetooth_searching_rounded
                                : Icons.watch_outlined,
                            color: ble.trackingSource == TrackingSource.directPhone
                                ? const Color(0xFF0284C7)
                                : const Color(0xFFA855F7),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ble.trackingSource == TrackingSource.directPhone
                                    ? "Phone Direct BLE Scanner"
                                    : 'Child Wristband Safety Tracker',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ble.trackingSource == TrackingSource.directPhone
                                    ? (ble.isScanning
                                        ? 'Measuring direct signal from phone to anchor nodes'
                                        : 'Scan stopped. Press button below to scan.')
                                    : (ble.isWristbandOnline
                                        ? 'Active Telemetry • Uplink Seq #${ble.wristbandSequence}'
                                        : 'Awaiting Wristband Beacon...'),
                                style: TextStyle(
                                  color: (ble.trackingSource == TrackingSource.directPhone
                                          ? ble.isScanning
                                          : ble.isWristbandOnline)
                                      ? const Color(0xFF10B981)
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (ble.trackingSource == TrackingSource.directPhone
                                    ? ble.isScanning
                                    : ble.isWristbandOnline)
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (ble.trackingSource == TrackingSource.directPhone
                                          ? ble.isScanning
                                          : ble.isWristbandOnline)
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                (ble.trackingSource == TrackingSource.directPhone
                                        ? (ble.isScanning ? 'ACTIVE' : 'IDLE')
                                        : (ble.isWristbandOnline ? 'ONLINE' : 'SEARCHING')),
                                style: TextStyle(
                                  color: (ble.trackingSource == TrackingSource.directPhone
                                          ? ble.isScanning
                                          : ble.isWristbandOnline)
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF94A3B8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
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
                      Expanded(
                        child: Text(
                          ble.statusMessage,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : const Color(0xFF475569),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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

              // Multi-Ring 2.4GHz Radar (strictly colored dots without distance text)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: RadarView(
                    nodes: ble.nodes,
                    trackingSource: ble.trackingSource,
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
                        '${ble.nodes.where((n) => (ble.trackingSource == TrackingSource.directPhone ? n.directState != NodeState.offline : n.wbState != NodeState.offline)).length}/${ble.nodes.length} ONLINE',
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
                      onRename: () => _showRenameDialog(context, node, ble),
                      onToggleFan: node.id == 1 ? ble.toggleFanState : null,
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

  Widget _buildTrackingSourceTab({
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
                ? activeColor.withValues(alpha: isDark ? 0.20 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: isDark ? 0.6 : 0.5)
                  : Colors.transparent,
              width: 1.2,
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
                        fontSize: 11.5,
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
                        fontSize: 9.5,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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

  void _showRenameDialog(BuildContext context, NodeData node, BleService ble) {
    final textController = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit_outlined, color: node.primaryColor, size: 22),
            const SizedBox(width: 8),
            Text('Rename Node ${node.id}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a custom name for this beacon appliance (e.g. Living Room Fan, Kitchen Iron, Balcony Door):',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Node Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: Icon(node.icon, color: node.primaryColor),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              final newName = textController.text.trim();
              if (newName.isNotEmpty) {
                ble.renameNode(node.id, newName);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showHelpGuide(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white30 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.help_center_outlined, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SHAPNEST Setup & Signal Guide',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Understanding dBm, Zones & Hardware Setup',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Section 1: What is dBm
                  _buildHelpCard(
                    isDark: isDark,
                    icon: Icons.signal_cellular_alt_rounded,
                    color: const Color(0xFF38BDF8),
                    title: 'What is dBm & Signal Strength (RSSI)?',
                    content: '• RSSI (Received Signal Strength Indicator) is measured in dBm (decibel-milliwatts).\n'
                        '• dBm is always a negative number. Closer to 0 means STRONGER signal (closer proximity).\n'
                        '• -40 dBm: Extremely close (< 30 cm).\n'
                        '• -60 dBm: Danger Red Zone threshold (child is very close).\n'
                        '• -74 dBm: Caution Yellow Zone threshold (child is approaching).\n'
                        '• Below -74 dBm: Safe Green Zone (child is far away).',
                  ),
                  const SizedBox(height: 14),

                  // Section 2: Tri-Zone Safety Logic
                  _buildHelpCard(
                    isDark: isDark,
                    icon: Icons.security_rounded,
                    color: const Color(0xFFFF5252),
                    title: 'The 3 Safety Zones & Condition Gating',
                    content: '🔴 Red Danger Zone (≥ -60 dBm):\n'
                        '   Child is dangerously close! Critical alerts and phone vibrations trigger ONLY IF the hazard condition is fulfilled (Fan is ON, Iron is HOT, or Door is OPEN)!\n'
                        '   If the hazard is OFF/Cool/Closed, alarms stay silent.\n\n'
                        '🟡 Yellow Caution Zone (-60 dBm to -74 dBm):\n'
                        '   Child is approaching the appliance. System provides caution warnings.\n\n'
                        '🟢 Green Safe Zone (< -74 dBm):\n'
                        '   Child is safely far away from the appliance.',
                  ),
                  const SizedBox(height: 14),

                  // Section 3: Hardware Setup Steps
                  _buildHelpCard(
                    isDark: isDark,
                    icon: Icons.checklist_rounded,
                    color: const Color(0xFF10B981),
                    title: 'Easy 5-Step Hardware Setup Guide',
                    content: '1. Power On Anchor Nodes:\n'
                        '   Plug in your ESP32 anchor nodes near the appliances (Fan, Iron, Door).\n\n'
                        '2. Fasten Child Wristband:\n'
                        '   Power on the ESP32 wristband and put it on your child.\n\n'
                        '3. Turn On Phone Bluetooth:\n'
                        '   Allow Bluetooth and Notification permissions for heads-up alerts.\n\n'
                        '4. Calibrate at 1 Meter:\n'
                        '   Stand exactly 1 meter away from each node and tap "CALIBRATE 1m" for precision.\n\n'
                        '5. Switch Tracking Source Anytime:\n'
                        '   Use the top toggle to switch between tracking the Child Wristband or checking directly with your Phone\'s Bluetooth.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpCard({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}
