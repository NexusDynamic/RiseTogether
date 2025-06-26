import 'package:rise_together/src/game/action_system.dart';

import '../local/local_action_bridge.dart';
import '../network_bridge.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
}) => LocalActionBridge(actionManager: actionManager);
