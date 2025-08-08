import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/services/network_coordinator.dart';

import 'network_bridge.dart';

NetworkBridge getNetworkBridge(
  ActionStreamManager actionManager, {
  bool useLocalNetwork = true,
  NetworkCoordinator? networkCoordinator,
}) => throw UnsupportedError('Cannot create an abstract NetworkBridge');
