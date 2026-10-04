import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import 'widgets/calibration_sheet.dart';
import 'widgets/diagnostic_sheet.dart';
import 'widgets/node_card.dart';
import 'widgets/radar_view.dart';

class HomeScreen extends StatefulWidget {
  final BleService bleService;

  const HomeScreen({super.key, required this.bleService});

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.bleService,
      builder: (context, child) {
        final ble = widget.bleService;

        return Scaffold(
          backgroundColor: const Color(0xFF020617), // Deep slate black
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F172A),
            elevation: 0,
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SHAPNEST',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Distance Engine (No-Hub Direct BLE)',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              // Dynamic Unit Toggle ('m' <-> 'cm')
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUnitButton('m'),
                    _buildUnitButton('cm'),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Simulation / Demo Mode Toggle
              IconButton(
                icon: Icon(
                  ble.isSimulating ? Icons.smart_toy : Icons.smart_toy_outlined,
                  color: ble.isSimulating ? const Color(0xFFA855F7) : Colors.white70,
                ),
                tooltip: ble.isSimulating ? 'Stop Demo Simulation' : 'Start Demo Simulation',
                onPressed: () => ble.toggleSimulation(),
              ),

              // Calibration Modal Button
              IconButton(
                icon: const Icon(Icons.tune, color: Color(0xFF00E5FF)),
                tooltip: 'Calibrate Distance Accuracy',
                onPressed: () => _openCalibration(1),
              ),

              // Diagnostic Log Modal Button
              IconButton(
                icon: const Icon(Icons.terminal, color: Colors.white70),
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
                    color: const Color(0xFFA855F7).withValues(alpha: 0.2),
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
                          child: const Text(
                            'EXIT',
                            style: TextStyle(
                              color: Colors.white,
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
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Row(
                      children: [
                        _buildModeTab(
                          title: 'Direct Phone Tracking',
                          subtitle: 'Phone ⟷ Nodes',
                          icon: Icons.smartphone,
                          isSelected: ble.trackingSource == TrackingSource.directPhone,
                          activeColor: const Color(0xFF00E5FF),
                          onTap: () => ble.setTrackingSource(TrackingSource.directPhone),
                        ),
                        const SizedBox(width: 4),
                        _buildModeTab(
                          title: 'Child Wristband',
                          subtitle: ble.isWristbandOnline ? 'Online (Seq #${ble.wristbandSequence})' : 'Offline',
                          icon: Icons.watch,
                          isSelected: ble.trackingSource == TrackingSource.wristband,
                          activeColor: const Color(0xFFA855F7),
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
                              : (ble.isSimulating ? const Color(0xFFA855F7) : const Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ble.statusMessage,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        'Exponent: n=${ble.distanceEngine.globalPathLossN.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
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
                      const Text(
                        'ANCHOR NODES TELEMETRY',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '${ble.nodes.where((n) => (ble.trackingSource == TrackingSource.directPhone ? n.directDistanceM : n.wbDistanceM) != null).length}/3 ACTIVE',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
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
              backgroundColor: ble.isScanning ? const Color(0xFFFF5252) : const Color(0xFF00E5FF),
              foregroundColor: ble.isScanning ? Colors.white : Colors.black,
              elevation: 8,
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

  Widget _buildUnitButton(String unit) {
    final isSelected = _unit == unit;
    return GestureDetector(
      onTap: () {
        setState(() {
          _unit = unit;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          unit,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white60,
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
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor.withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: isSelected ? activeColor : Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected ? activeColor : Colors.white38,
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
