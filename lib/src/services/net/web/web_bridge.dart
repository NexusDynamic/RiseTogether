import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/services/network_coordinator.dart';

import '../local/local_action_bridge.dart';
import '../network_bridge.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
  NetworkCoordinator? networkCoordinator,
}) => LocalActionBridge(actionManager: actionManager);
