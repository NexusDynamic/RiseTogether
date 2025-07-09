import 'dart:async';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart' hide PlayerAction;
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

  // Simple LSL outlet for game data
  LSLOutlet? _gameDataOutlet;
  // LSL inlets for receiving game data from all nodes
  final List<LSLInlet> _gameDataInlets = [];
  final List<StreamSubscription> _inletSubscriptions = [];
  
  bool _isInitialized = false;
  bool _isPausedMode = false;

  // Mapping from playerIdHash back to original playerId for own messages
  final Map<int, String> _playerIdMapping = {};

  // Optional coordination manager to reuse existing LSL coordination
  final CoordinationManager? _coordinationManager;
  
  // Timer for periodic inlet discovery
  Timer? _inletDiscoveryTimer;

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

    appLog.info('Initializing NetworkActionBridge with simple LSL transport');

    try {
      await _initializeSimpleGameTransport();
      _isInitialized = true;
      appLog.info('NetworkActionBridge initialized successfully');
    } catch (e) {
      appLog.severe('Failed to initialize NetworkActionBridge: $e');
      rethrow;
    }
  }

  /// Initialize in paused mode (low frequency, no busy wait)
  Future<void> initializePausedMode() async {
    if (_isInitialized) return;

    appLog.info('Initializing NetworkActionBridge in paused mode with simple LSL transport');
    _isPausedMode = true;

    try {
      await _initializeSimpleGameTransport(pausedMode: true);
      _isInitialized = true;
      appLog.info('NetworkActionBridge initialized successfully in paused mode');
    } catch (e) {
      appLog.severe('Failed to initialize NetworkActionBridge in paused mode: $e');
      rethrow;
    }
  }

  /// Activate full mode (enable busy-wait polling)
  Future<void> activateFullMode() async {
    if (!_isInitialized) {
      appLog.warning('NetworkActionBridge not initialized, cannot activate full mode');
      return;
    }

    if (!_isPausedMode) {
      appLog.info('Already in full mode');
      return;
    }

    appLog.info('Activating full mode (increasing polling frequency)');
    _isPausedMode = false;

    // Start more frequent inlet discovery for active gameplay
    _startInletDiscovery(frequent: true);
    
    appLog.info('Full mode activated successfully');
  }

  /// Pause mode (disable busy-wait polling)
  Future<void> pauseMode() async {
    if (!_isInitialized) {
      appLog.warning('NetworkActionBridge not initialized, cannot pause mode');
      return;
    }

    if (_isPausedMode) {
      appLog.info('Already in paused mode');
      return;
    }

    appLog.info('Pausing mode (reducing polling frequency)');
    _isPausedMode = true;

    // Reduce inlet discovery frequency for paused mode
    _startInletDiscovery(frequent: false);
    
    appLog.info('Paused mode activated successfully');
  }

  /// Initialize simple game transport with LSL outlet and inlets
  Future<void> _initializeSimpleGameTransport({bool pausedMode = false}) async {
    appLog.info('Creating simple LSL game transport${pausedMode ? ' (paused mode)' : ''}');

    // Create LSL outlet for sending game data
    final streamName = 'risetogether_actions_$deviceId';
    final streamInfo = LSLStreamInfo(
      name: streamName,
      type: 'GameActions',
      channelCount: 3, // [teamId, actionIndex, playerIdHash]
      nominalSampleRate: pausedMode ? 60.0 : 500.0,
      channelFormat: LSLChannelFormat.int32,
      sourceId: 'game_$deviceId',
    );

    // Add metadata
    streamInfo.setMetadata('device_id', deviceId);
    streamInfo.setMetadata('device_name', deviceName);
    streamInfo.setMetadata('game_version', '0.4.0');

    _gameDataOutlet = LSLOutlet(streamInfo);
    appLog.info('Created LSL outlet: $streamName');

    // Start discovering inlets from other nodes
    _startInletDiscovery(frequent: !pausedMode);
    
    // Give some time for initial discovery
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Start discovering LSL inlets from other nodes
  void _startInletDiscovery({bool frequent = false}) {
    _inletDiscoveryTimer?.cancel();
    
    final interval = frequent ? const Duration(seconds: 2) : const Duration(seconds: 5);
    
    _inletDiscoveryTimer = Timer.periodic(interval, (timer) {
      _discoverGameInlets();
    });
    
    // Do immediate discovery
    _discoverGameInlets();
  }

  /// Discover and connect to LSL inlets from other nodes
  void _discoverGameInlets() {
    try {
      // Find all available game action streams
      final availableStreams = LSLStreamInfo.resolveStreams(
        predicate: LSLStreamPredicate(type: 'GameActions'),
        timeout: 1.0,
      );

      for (final streamInfo in availableStreams) {
        final sourceId = streamInfo.sourceId;
        
        // Don't connect to our own stream
        if (sourceId == 'game_$deviceId') continue;
        
        // Check if we already have an inlet for this stream
        final existingInlets = _gameDataInlets.where(
          (inlet) => inlet.info.sourceId == sourceId,
        ).toList();
        
        final existingInlet = existingInlets.isEmpty ? null : existingInlets.first;
        
        if (existingInlet == null) {
          appLog.info('Connecting to new game stream: ${streamInfo.name} (${streamInfo.sourceId})');
          _connectToGameInlet(streamInfo);
        }
      }
    } catch (e) {
      appLog.warning('Error discovering game inlets: $e');
    }
  }

  /// Connect to a specific game inlet
  void _connectToGameInlet(LSLStreamInfo streamInfo) {
    try {
      final inlet = LSLInlet(streamInfo);
      _gameDataInlets.add(inlet);
      
      // Listen to data from this inlet
      final subscription = inlet.dataStream.listen(
        (sample) => _processGameDataSample(sample, streamInfo.sourceId),
        onError: (error) {
          appLog.warning('Error in game data stream from ${streamInfo.sourceId}: $error');
        },
      );
      
      _inletSubscriptions.add(subscription);
      appLog.info('Connected to game stream: ${streamInfo.name}');
    } catch (e) {
      appLog.severe('Failed to connect to game inlet ${streamInfo.name}: $e');
    }
  }

  /// Send action over network using LSL outlet
  @override
  void sendAction(int teamId, String playerId, PaddleAction action) {
    if (!_isInitialized || _gameDataOutlet == null) {
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
      _gameDataOutlet!.pushSample([teamId, action.index, playerIdHash]);
    } catch (e) {
      appLog.severe('Failed to send action over network: $e');
    }
  }

  /// Get original playerId from hash for own messages
  String _getOriginalPlayerId(int playerIdHash) {
    return _playerIdMapping[playerIdHash] ?? 'unknown_$playerIdHash';
  }

  /// Process game data sample from LSL inlet
  void _processGameDataSample(List<int> sample, String sourceId) {
    try {
      // Decode the 3-channel data: [teamId, actionIndex, playerIdHash]
      if (sample.length >= 3) {
        final teamId = sample[0];
        final actionIndex = sample[1];
        final playerIdHash = sample[2];

        // Validate action index
        if (actionIndex < 0 || actionIndex >= PaddleAction.values.length) {
          appLog.warning('Invalid action index: $actionIndex');
          return;
        }

        final action = PaddleAction.values[actionIndex];
        // Create consistent playerId based on source and hash
        final playerId = sourceId == 'game_$deviceId'
            ? _getOriginalPlayerId(playerIdHash)
            : 'remote_${sourceId}_$playerIdHash';

        // Add action to appropriate team stream
        final teamStream = actionManager.getTeamStream(teamId);
        if (teamStream != null) {
          teamStream.addAction(PlayerAction(playerId, action));

          appLog.finest(
            'Received action: team=$teamId, player=$playerId, action=$action from $sourceId',
          );
        } else {
          appLog.warning('No team stream found for team $teamId');
        }
      } else {
        appLog.warning(
          'Incomplete game data sample: $sample',
        );
      }
    } catch (e) {
      appLog.severe('Error processing network action: $e');
    }
  }

  /// Remove player from network tracking
  @override
  void removePlayer(int teamId, String playerId) {
    appLog.fine('Removing player: team=$teamId, player=$playerId');
    final teamStream = actionManager.getTeamStream(teamId);
    teamStream?.removePlayer(playerId);
  }

  /// Get performance metrics for monitoring network performance
  Map<String, dynamic>? getPerformanceMetrics() {
    return {
      'outlet_active': _gameDataOutlet != null,
      'inlet_count': _gameDataInlets.length,
      'paused_mode': _isPausedMode,
    };
  }

  /// Get current network status
  String getNetworkStatus() {
    if (!_isInitialized) {
      return 'Not initialized';
    }

    final outletStatus = _gameDataOutlet != null ? 'Active' : 'None';
    final inletCount = _gameDataInlets.length;
    final mode = _isPausedMode ? 'Paused' : 'Active';

    return 'Outlet: $outletStatus, Inlets: $inletCount, Mode: $mode';
  }

  /// Dispose resources
  @override
  void dispose() {
    appLog.info('Disposing NetworkActionBridge');

    _inletDiscoveryTimer?.cancel();
    _inletDiscoveryTimer = null;

    // Cancel all inlet subscriptions
    for (final subscription in _inletSubscriptions) {
      subscription.cancel();
    }
    _inletSubscriptions.clear();

    // Close all inlets
    for (final inlet in _gameDataInlets) {
      inlet.close();
    }
    _gameDataInlets.clear();

    // Close outlet
    _gameDataOutlet?.close();
    _gameDataOutlet = null;

    _isInitialized = false;
  }
}
