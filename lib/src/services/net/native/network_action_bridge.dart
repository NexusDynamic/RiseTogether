import 'dart:async';
import 'package:liblsl_coordinator/liblsl_coordinator.dart'
    hide PlayerAction; // hide for now
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/coordination_manager.dart';

import '../network_bridge.dart';
import '../network_config.dart';

/// Bridge between network layer and action system using LSL coordination
class NetworkActionBridge with AppLogging implements NetworkBridge {
  final ActionStreamManager actionManager;
  final String deviceId;
  final String deviceName;
  final PerformancePreset performancePreset;

  GamingCoordinationNode? _gamingNode;
  StreamSubscription? _gameDataSubscription;
  bool _isInitialized = false;

  // Mapping from playerIdHash back to original playerId for own messages
  final Map<int, String> _playerIdMapping = {};

  // Optional coordination manager to reuse existing LSL coordination
  final CoordinationManager? _coordinationManager;

  NetworkActionBridge({
    required this.actionManager,
    String? deviceId,
    String? deviceName,
    this.performancePreset = PerformancePreset.balanced,
    CoordinationManager? coordinationManager,
  }) : deviceId = deviceId ?? RiseTogetherNetworkConfig.generateDeviceId(),
       deviceName =
           deviceName ?? RiseTogetherNetworkConfig.generateDeviceName(),
       _coordinationManager = coordinationManager;

  /// Initialize network connections using existing coordination
  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    appLog.info('Initializing NetworkActionBridge');

    try {
      if (_coordinationManager != null && _coordinationManager.isInitialized) {
        appLog.info('Reusing existing coordination manager for game data');

        // Use existing coordination manager's game streaming capabilities
        await _initializeFromCoordinationManager();
      } else {
        appLog.info('Creating new gaming node (fallback mode)');

        // Fall back to creating a new gaming node
        await _initializeStandaloneGamingNode();
      }

      // Set up listener for incoming game actions
      _setupNetworkReceiver();

      // Wait briefly to establish connections
      await Future.delayed(const Duration(milliseconds: 500));

      _isInitialized = true;
      appLog.info('NetworkActionBridge initialized successfully');

      if (_gamingNode != null) {
        appLog.info('Device role: ${_gamingNode!.role}');
      }
    } catch (e) {
      appLog.severe('Failed to initialize NetworkActionBridge: $e');
      rethrow;
    }
  }

  /// Initialize using existing coordination manager
  Future<void> _initializeFromCoordinationManager() async {
    final coordManager = _coordinationManager!;

    // CoordinationManager has LSLCoordinationNode, we need to create a GamingCoordinationNode
    // that reuses the same LSL infrastructure but adds game data streaming
    if (coordManager.coordinationNode != null) {
      final existingNode = coordManager.coordinationNode!;
      appLog.info(
        'Creating GamingCoordinationNode that reuses existing LSL coordination',
      );

      // Create a gaming node that uses the same nodeId and nodeName but different stream names
      _gamingNode = GamingCoordinationNode(
        nodeId: existingNode.nodeId,
        nodeName: existingNode.nodeName,
        coordinationStreamName:
            'risetogether_coordination', // Same as coordination manager
        gameDataStreamName: 'risetogether_actions',
        coordinationConfig:
            RiseTogetherNetworkConfig.createCoordinationConfig(),
        gameDataConfig: RiseTogetherNetworkConfig.createPerformancePreset(
          performancePreset,
        ),
      );

      // Initialize game data capabilities only (coordination already exists)
      await _gamingNode!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          appLog.warning('Gaming node initialization timed out');
          throw TimeoutException(
            'Gaming node initialization timed out',
            const Duration(seconds: 10),
          );
        },
      );

      // Join the existing coordination network
      await _gamingNode!.join().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          appLog.warning('Gaming node join timed out');
          throw TimeoutException(
            'Gaming node join timed out',
            const Duration(seconds: 10),
          );
        },
      );
    } else {
      appLog.warning(
        'Coordination manager has no coordination node, creating standalone',
      );
      await _initializeStandaloneGamingNode();
    }
  }

  /// Initialize standalone gaming node (fallback)
  Future<void> _initializeStandaloneGamingNode() async {
    _gamingNode = GamingCoordinationNode(
      nodeId: deviceId,
      nodeName: deviceName,
      coordinationStreamName:
          'risetogether_coordination_game', // Different stream to avoid conflict
      gameDataStreamName: 'risetogether_actions',
      coordinationConfig: RiseTogetherNetworkConfig.createCoordinationConfig(),
      gameDataConfig: RiseTogetherNetworkConfig.createPerformancePreset(
        performancePreset,
      ),
    );

    // Initialize the gaming node with timeout
    await _gamingNode!.initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        appLog.warning('Gaming node initialization timed out');
        throw TimeoutException(
          'Gaming node initialization timed out',
          const Duration(seconds: 10),
        );
      },
    );

    await _gamingNode!.join().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        appLog.warning('Gaming node join timed out');
        throw TimeoutException(
          'Gaming node join timed out',
          const Duration(seconds: 10),
        );
      },
    );
  }

  /// Send action over network using high-frequency LSL transport
  @override
  void sendAction(int teamId, String playerId, PaddleAction action) {
    if (!_isInitialized || _gamingNode == null) {
      appLog.warning('NetworkActionBridge not initialized, action ignored');
      return;
    }

    appLog.fine(
      'Sending action: team=$teamId, player=$playerId, action=$action',
    );

    try {
      // Convert playerId to a hash for compact transmission
      final playerIdHash = playerId.hashCode;

      // Store mapping to reconstruct original playerId when we receive our own messages
      _playerIdMapping[playerIdHash] = playerId;

      // Send action as 3-channel int data: [teamId, actionIndex, playerIdHash]
      _gamingNode!.sendGameData([teamId, action.index, playerIdHash]);
    } catch (e) {
      appLog.severe('Failed to send action over network: $e');
    }
  }

  /// Get original playerId from hash for own messages
  String _getOriginalPlayerId(int playerIdHash) {
    return _playerIdMapping[playerIdHash] ?? 'unknown_$playerIdHash';
  }

  /// Setup receiver for network actions using high-frequency transport
  void _setupNetworkReceiver() {
    appLog.fine('Setting up high-frequency network receiver');

    if (_gamingNode == null) return;

    // Listen to game data samples from other devices
    _gameDataSubscription = _gamingNode!.gameEventStream.listen(
      (sampleEvent) {
        try {
          final sample = GameDataSample.fromMap(sampleEvent.data);
          // In network mode, process all messages including our own
          // (coordinator connects to its own LSL outlet)

          // Decode the 3-channel data: [teamId, actionIndex, playerIdHash]
          if (sample.channelData.length >= 3) {
            final teamId = sample.channelData[0] as int;
            final actionIndex = sample.channelData[1] as int;
            final playerIdHash = sample.channelData[2] as int;

            // Validate action index
            if (actionIndex < 0 || actionIndex >= PaddleAction.values.length) {
              appLog.warning('Invalid action index: $actionIndex');
              return;
            }

            final action = PaddleAction.values[actionIndex];
            // Create consistent playerId based on source and hash
            final playerId = sample.sourceId == 'game_$deviceId'
                ? _getOriginalPlayerId(playerIdHash)
                : 'remote_${sample.sourceId}_$playerIdHash';

            // Add action to appropriate team stream
            final teamStream = actionManager.getTeamStream(teamId);
            if (teamStream != null) {
              teamStream.addAction(PlayerAction(playerId, action));

              appLog.finest(
                'Received action: team=$teamId, player=$playerId, action=$action, '
                'timeCorrection=${sample.timeCorrection?.toStringAsFixed(3)}s',
              );
            } else {
              appLog.warning('No team stream found for team $teamId');
            }
          } else {
            appLog.warning(
              'Incomplete game data sample: ${sample.channelData}',
            );
          }
        } catch (e) {
          appLog.severe('Error processing network action: $e');
        }
      },
      onError: (error) {
        appLog.severe('Error in game data stream: $error');
      },
    );

    // Also listen to coordination events for debugging
    _gamingNode!.eventStream.listen((event) {
      appLog.info('Coordination event: $event');
    });
  }

  /// Remove player from network tracking
  @override
  void removePlayer(int teamId, String playerId) {
    appLog.fine('Removing player: team=$teamId, player=$playerId');
    final teamStream = actionManager.getTeamStream(teamId);
    teamStream?.removePlayer(playerId);
  }

  /// Get performance metrics for monitoring network performance
  HighFrequencyMetrics? getPerformanceMetrics() {
    return _gamingNode?.gamePerformanceMetrics;
  }

  /// Get current network status
  String getNetworkStatus() {
    if (!_isInitialized || _gamingNode == null) {
      return 'Not initialized';
    }

    final role = _gamingNode!.role;
    final participants = _gamingNode!.gameParticipants.length;
    final metrics = _gamingNode!.gamePerformanceMetrics;

    return 'Role: $role, Participants: $participants, '
        'Frequency: ${metrics.actualFrequency.toStringAsFixed(1)}Hz, '
        'Samples: ${metrics.samplesProcessed}';
  }

  /// Dispose resources
  @override
  void dispose() {
    appLog.info('Disposing NetworkActionBridge');

    _gameDataSubscription?.cancel();
    _gameDataSubscription = null;

    _gamingNode?.dispose();
    _gamingNode = null;

    _isInitialized = false;
  }
}
