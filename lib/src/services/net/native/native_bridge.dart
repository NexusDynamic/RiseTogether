import 'package:rise_together/src/game/action_system.dart';

import '../local/local_action_bridge.dart';
import 'network_action_bridge.dart';
import '../network_bridge.dart';
import '../network_config.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
  String? deviceId,
  String? deviceName,
  dynamic performancePreset,
  dynamic coordinationManager,
}) => useLocalNetwork
    ? LocalActionBridge(actionManager: actionManager)
    : NetworkActionBridge(
        actionManager: actionManager,
        deviceId: deviceId,
        deviceName: deviceName,
        performancePreset: performancePreset ?? PerformancePreset.balanced,
        coordinationManager: coordinationManager,
      );
