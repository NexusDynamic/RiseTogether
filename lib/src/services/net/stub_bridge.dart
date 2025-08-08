import 'package:rise_together/src/game/action_system.dart';

import 'network_bridge.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
  String? deviceId,
  String? deviceName,
  dynamic performancePreset,
  dynamic coordinationManager,
}) => throw UnsupportedError('Cannot create an abstract NetworkBridge');
