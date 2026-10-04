import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/ble_service.dart';

class DiagnosticSheet extends StatelessWidget {
  final BleService bleService;

  const DiagnosticSheet({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: bleService,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

              // Title and Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.terminal,
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Live Diagnostic Console',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.share,
                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                          size: 20,
                        ),
                        tooltip: 'Share Diagnostic Logs',
                        onPressed: () {
                          if (bleService.diagnosticLogs.isNotEmpty) {
                            SharePlus.instance.share(
                              ShareParams(
                                text: bleService.diagnosticLogs.join('\n'),
                                subject: 'SHAPNEST Diagnostic Telemetry Log',
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Node Packet Rate Table
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: bleService.nodes.map((node) {
                    return Column(
                      children: [
                        Text(
                          node.name,
                          style: TextStyle(
                            color: node.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${node.packetsPerSecond.toStringAsFixed(1)} Hz',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          '${node.packetCount} pkts',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 12),

              // Console Log Output
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A), // Dark terminal background for optimal log readability
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: bleService.diagnosticLogs.isEmpty
                      ? const Center(
                          child: Text(
                            'No logs yet. Start scanning to view live BLE telemetry.',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          itemCount: bleService.diagnosticLogs.length,
                          itemBuilder: (context, index) {
                            final log = bleService.diagnosticLogs[index];
                            Color textColor = const Color(0xFF94A3B8);
                            if (log.contains('# [ERROR]')) {
                              textColor = const Color(0xFFFF5252);
                            } else if (log.contains('# [WARN]')) {
                              textColor = const Color(0xFFFBBF24);
                            } else if (log.contains('# [CALIBRATION]')) {
                              textColor = const Color(0xFF00E5FF);
                            } else if (log.contains('# [SIMULATION]')) {
                              textColor = const Color(0xFFA855F7);
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                log,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  height: 1.3,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
