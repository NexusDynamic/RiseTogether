import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/services/network_coordinator.dart';

import '../local/local_action_bridge.dart';
import 'network_action_bridge.dart';
import '../network_bridge.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
  NetworkCoordinator? networkCoordinator,
}) => useLocalNetwork
    ? LocalActionBridge(actionManager: actionManager)
    : NetworkActionBridge(
        actionManager: actionManager,
        coordinator: networkCoordinator!,
      );
