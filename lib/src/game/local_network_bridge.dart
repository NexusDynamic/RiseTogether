import 'dart:async';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/game/network_action_bridge.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Local network implementation for testing without LSL
/// Allows multiple players on the same device
class LocalNetworkBridge with AppLogging implements NetworkBridge {
  final ActionStreamManager actionManager;
  
  LocalNetworkBridge({required this.actionManager});

  /// Initialize local network (no-op for local testing)
  @override
  Future<void> initialize() async {
    appLog.info('Initializing LocalNetworkBridge for local testing');
  }

  /// Send action locally (directly to action stream)
  @override
  void sendAction(int teamId, String playerId, PaddleAction action) {
    appLog.fine('Local action: team=$teamId, player=$playerId, action=$action');
    
    final teamStream = actionManager.getTeamStream(teamId);
    if (teamStream != null) {
      teamStream.addAction(PlayerAction(playerId, action));
    } else {
      appLog.warning('No team stream found for team $teamId');
    }
  }

  /// Remove player from local tracking
  @override
  void removePlayer(int teamId, String playerId) {
    appLog.fine('Removing local player: team=$teamId, player=$playerId');
    final teamStream = actionManager.getTeamStream(teamId);
    teamStream?.removePlayer(playerId);
  }

  /// Dispose resources (no-op for local)
  @override
  void dispose() {
    appLog.info('Disposing LocalNetworkBridge');
  }
}

/// Factory for creating network bridges
class NetworkBridgeFactory {
  static NetworkActionBridge createLSLBridge(ActionStreamManager actionManager) {
    return NetworkActionBridge(actionManager: actionManager);
  }
  
  static LocalNetworkBridge createLocalBridge(ActionStreamManager actionManager) {
    return LocalNetworkBridge(actionManager: actionManager);
  }
}