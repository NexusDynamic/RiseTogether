import 'dart:async';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/network_coordinator.dart';

import '../network_bridge.dart';

/// Bridge between network layer and action system using NetworkCoordinator
class NetworkActionBridge with AppLogging implements NetworkBridge {
  final ActionStreamManager actionManager;
  final NetworkCoordinator coordinator;

  bool _isInitialized = false;

  NetworkActionBridge({required this.actionManager, required this.coordinator});

  /// Initialize network connections using coordinator
  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    appLog.info('Initializing NetworkActionBridge with coordinator');

    try {
      // Ensure coordinator is initialized
      if (!coordinator.isInitialized) {
        await coordinator.initialize();
      }

      _isInitialized = true;
      appLog.info('NetworkActionBridge initialized successfully');
    } catch (e) {
      appLog.severe('Failed to initialize NetworkActionBridge: $e');
      rethrow;
    }
  }

  /// Send action over network using coordinator
  @override
  void sendAction(int teamId, String playerId, PaddleAction action) {
    if (!_isInitialized) {
      appLog.warning('NetworkActionBridge not initialized, action ignored');
      return;
    }

    appLog.fine(
      'Sending action: team=$teamId, player=$playerId, action=$action',
    );

    try {
      // Send through coordinator's network layer
      coordinator.sendGameAction(teamId, playerId, action);
    } catch (e) {
      appLog.severe('Failed to send action over network: $e');
    }
  }

  /// Remove player from network tracking
  @override
  void removePlayer(int teamId, String playerId) {
    appLog.fine('Removing player: team=$teamId, player=$playerId');
    final teamStream = actionManager.getTeamStream(teamId);
    teamStream?.removePlayer(playerId);
  }

  /// Get current network status from coordinator
  String getNetworkStatus() {
    if (!_isInitialized) {
      return 'Not initialized';
    }

    if (!coordinator.networkingEnabled) {
      return 'Local mode';
    }

    final nodeCount = coordinator.connectedNodes.length;
    final role = coordinator.isCoordinator ? 'Coordinator' : 'Participant';
    final gameStatus = coordinator.gameActive ? 'Game Active' : 'Lobby';

    return '$role, Nodes: $nodeCount, $gameStatus';
  }

  /// Get performance metrics for monitoring
  Map<String, dynamic>? getPerformanceMetrics() {
    return {
      'coordinator_initialized': coordinator.isInitialized,
      'networking_enabled': coordinator.networkingEnabled,
      'node_count': coordinator.connectedNodes.length,
      'is_coordinator': coordinator.isCoordinator,
      'game_active': coordinator.gameActive,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    appLog.info('Disposing NetworkActionBridge');
    _isInitialized = false;
    // Note: Don't dispose coordinator here as it's shared
  }
}
