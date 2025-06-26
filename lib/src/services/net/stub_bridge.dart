import 'package:rise_together/src/game/action_system.dart';

import 'network_bridge.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
}) => throw UnsupportedError('Cannot create an abstract NetworkBridge');
