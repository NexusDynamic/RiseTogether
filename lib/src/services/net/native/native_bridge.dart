import 'package:rise_together/src/game/action_system.dart';

import '../local/local_action_bridge.dart';
import 'network_action_bridge.dart';
import '../network_bridge.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
}) => useLocalNetwork
    ? LocalActionBridge(actionManager: actionManager)
    : NetworkActionBridge(actionManager: actionManager);
