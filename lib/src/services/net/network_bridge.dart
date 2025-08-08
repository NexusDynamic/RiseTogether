import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/services/network_coordinator.dart';
import 'stub_bridge.dart'
    if (dart.library.js_interop) 'web/web_bridge.dart' // Web/WASM
    if (dart.library.io) 'native/native_bridge.dart'; // Native

/// Common interface for network bridges
abstract class NetworkBridge {
  Future<void> initialize();
  void sendAction(int teamId, String playerId, PaddleAction action);
  void removePlayer(int teamId, String playerId);
  void dispose();
  factory NetworkBridge(
    ActionStreamManager actionManager, {
    bool useLocalNetwork = true,
    NetworkCoordinator? networkCoordinator,
  }) => getNetworkBridge(
    actionManager,
    useLocalNetwork: useLocalNetwork,
    networkCoordinator: networkCoordinator,
  );
}
