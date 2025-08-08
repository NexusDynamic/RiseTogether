import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart' hide PlayerAction;
import 'package:rise_together/src/services/net/network_config.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/models/player_action.dart';

/// Player assignment for a node
class PlayerAssignment {
  final String nodeId;
  final String nodeName;
  final int teamId;
  final String playerId;
  final bool isCoordinator;

  PlayerAssignment({
    required this.nodeId,
    required this.nodeName,
    required this.teamId,
    required this.playerId,
    required this.isCoordinator,
  });

  Map<String, dynamic> toMap() => {
    'nodeId': nodeId,
    'nodeName': nodeName,
    'teamId': teamId,
    'playerId': playerId,
    'isCoordinator': isCoordinator,
  };

  factory PlayerAssignment.fromMap(Map<String, dynamic> map) =>
      PlayerAssignment(
        nodeId: map['nodeId'],
        nodeName: map['nodeName'],
        teamId: map['teamId'],
        playerId: map['playerId'],
        isCoordinator: map['isCoordinator'],
      );
}

/// Modern network coordinator using MultiLayerCoordinator
class NetworkCoordinator extends ChangeNotifier with AppLogging {
  MultiLayerCoordinator? _multiLayerCoordinator;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _gameDataSubscription;

  bool _isInitialized = false;
  bool _networkingEnabled = true;
  bool _gameActive = false;
  String? _deviceId;
  String? _deviceName;

  final List<NetworkNode> _connectedNodes = [];
  final Map<String, PlayerAssignment> _playerAssignments = {};

  // Game action streaming
  ActionStreamManager? _actionManager;
  CoordinationLayer? _gameLayer;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isCoordinator =>
      _multiLayerCoordinator?.role == NodeRole.coordinator;
  bool get networkingEnabled => _networkingEnabled;
  bool get gameActive => _gameActive;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  List<NetworkNode> get connectedNodes => List.unmodifiable(_connectedNodes);
  List<PlayerAssignment> get playerAssignments =>
      _playerAssignments.values.toList();
  MultiLayerCoordinator? get coordinationNode => _multiLayerCoordinator;
  ActionStreamManager? get actionManager => _actionManager;

  /// Initialize with networking enabled/disabled
  Future<void> initialize({bool enableNetworking = true}) async {
    if (_isInitialized) return;

    _networkingEnabled = enableNetworking;
    appLog.info(
      'Initializing NetworkCoordinator (networking: $_networkingEnabled)',
    );

    if (!_networkingEnabled) {
      _isInitialized = true;
      _setupLocalMode();
      notifyListeners();
      return;
    }

    try {
      _deviceId = RiseTogetherNetworkConfig.generateDeviceId();
      _deviceName = RiseTogetherNetworkConfig.generateDeviceName();

      // Create protocol config with coordination and game layers
      final protocolConfig = ProtocolConfig(
        protocolId: 'risetogether',
        protocolName: 'RiseTogether Multi-Layer Protocol',
        layers: [
          // Coordination layer for player management, team assignments, etc
          StreamLayerConfig(
            layerId: 'coordination',
            layerName: 'RiseTogether Coordination',
            streamConfig: StreamConfig(
              streamName: 'risetogether_coordination_$_deviceId',
              streamType: LSLContentType.markers,
              channelCount: 1,
              sampleRate:
                  LSL_IRREGULAR_RATE, // Low frequency for coordination messages
              channelFormat: LSLChannelFormat.string,
            ),
            isPausable: false,
            priority: LayerPriority.high,
          ),
          // Game data layer for high-frequency paddle actions
          StreamLayerConfig(
            layerId: 'gamedata',
            layerName: 'RiseTogether Game Actions',
            streamConfig: StreamConfig(
              streamName: 'risetogether_actions_$_deviceId',
              streamType: LSLContentType.markers,
              channelCount: 3, // [teamId, actionIndex, playerIdHash]
              sampleRate: 120.0, // High frequency for game actions
              channelFormat: LSLChannelFormat.int32,
            ),
            isPausable: true,
            priority: LayerPriority.high,
          ),
        ],
      );

      // Create multi-layer coordinator
      _multiLayerCoordinator = MultiLayerCoordinator(
        nodeId: _deviceId!,
        nodeName: _deviceName!,
        protocolConfig: protocolConfig,
        coordinationConfig:
            RiseTogetherNetworkConfig.createCoordinationConfig(),
      );

      // Initialize and join network
      await _multiLayerCoordinator!.initialize();
      await _multiLayerCoordinator!.join();

      _setupEventListeners();
      _setupGameDataLayer();
      _setupGameActionManager();

      _isInitialized = true;
      appLog.info(
        'NetworkCoordinator initialized - Role: ${_multiLayerCoordinator!.role}',
      );

      // Set up default assignments if we're coordinator
      if (isCoordinator) {
        _setupDefaultAssignments();
      }

      notifyListeners();
    } catch (e) {
      appLog.severe('Failed to initialize NetworkCoordinator: $e');
      rethrow;
    }
  }

  void _setupLocalMode() {
    // Set up for single device gameplay
    _deviceId = 'local_device';
    _deviceName = 'Local Player';

    _setupGameActionManager();

    // Add local player assignment
    _playerAssignments[_deviceId!] = PlayerAssignment(
      nodeId: _deviceId!,
      nodeName: _deviceName!,
      teamId: 0,
      playerId: 'currentPlayer',
      isCoordinator: true,
    );

    appLog.info('NetworkCoordinator initialized in local mode');
  }

  void _setupGameActionManager() {
    _actionManager = ActionStreamManager();
    appLog.info('Game action manager initialized');
  }

  void _setupGameDataLayer() {
    if (_multiLayerCoordinator == null) return;

    _gameLayer = _multiLayerCoordinator!.getLayer('gamedata');
    if (_gameLayer != null) {
      // Subscribe to game data from all other nodes
      _gameDataSubscription = _gameLayer!.dataStream.listen(
        _handleGameDataEvent,
      );
      appLog.info('Game data layer set up for high-frequency actions');
    }
  }

  void _setupEventListeners() {
    if (_multiLayerCoordinator == null) return;

    _eventSubscription = _multiLayerCoordinator!.eventStream.listen((event) {
      appLog.info('Coordination event: ${event.runtimeType}');

      switch (event) {
        case TopologyChangedEvent():
          _updateNodeList();
          break;
        case RoleChangedEvent():
          appLog.info('Role changed to: ${_multiLayerCoordinator!.role}');
          if (isCoordinator) {
            _setupDefaultAssignments();
            // Give the coordinator a moment to set up protocol, then refresh layers
            Future.delayed(Duration(milliseconds: 500), () {
              appLog.info('Checking game layer after coordinator promotion...');
              _refreshGameLayer();
            });
          }
          break;
        case ApplicationEvent():
          _handleApplicationEvent(event);
          break;
        case NodeJoinedEvent():
          _updateNodeList();
          _handleNewPlayerJoining(event);
          break;
        case NodeLeftEvent():
          _updateNodeList();
          break;
      }

      notifyListeners();
    });
  }

  void _handleApplicationEvent(ApplicationEvent event) {
    appLog.info('Application event: ${event.type}');

    switch (event.type) {
      case 'player_assignments':
        if (!isCoordinator) {
          final assignmentsData =
              event.data['assignments'] as Map<String, dynamic>?;
          if (assignmentsData != null) {
            _playerAssignments.clear();
            for (final entry in assignmentsData.entries) {
              _playerAssignments[entry.key] = PlayerAssignment.fromMap(
                entry.value,
              );
            }
            appLog.info(
              'Received player assignments: ${_playerAssignments.length} assignments',
            );
          }
        }
        break;
      case 'protocol_ready':
        // Protocol is ready, layers should now be functional
        appLog.info('Protocol ready - layers should now be functional');
        _refreshGameLayer();
        break;
    }
  }

  void _refreshGameLayer() {
    // Re-get the game layer in case it was replaced
    if (_multiLayerCoordinator != null) {
      _gameLayer = _multiLayerCoordinator!.getLayer('gamedata');
      appLog.info('Game layer refreshed: ${_gameLayer?.runtimeType}');
      
      // Re-establish the data stream subscription after layer replacement
      _gameDataSubscription?.cancel();
      if (_gameLayer != null) {
        _gameDataSubscription = _gameLayer!.dataStream.listen(
          _handleGameDataEvent,
        );
        appLog.info('Game data stream subscription re-established');
      }
    }
  }

  void _handleGameDataEvent(LayerDataEvent event) {
    // Only process game data events from the gamedata layer
    if (event.layerId != 'gamedata' || !_gameActive || _actionManager == null)
      return;

    final sample = event.data;
    if (sample.length >= 3) {
      try {
        final teamId = sample[0] as int;
        final actionIndex = sample[1] as int;
        final playerIdHash = sample[2] as int;

        if (actionIndex >= 0 && actionIndex < PaddleAction.values.length) {
          final action = PaddleAction.values[actionIndex];
          final playerId = 'remote_${event.sourceNodeId}_$playerIdHash';

          final teamStream = _actionManager!.getTeamStream(teamId);
          teamStream?.addAction(GameAction(playerId, action));

          appLog.finest(
            'Received network action: team=$teamId, player=$playerId, action=$action from ${event.sourceNodeId}',
          );
        }
      } catch (e) {
        appLog.warning('Error processing game data event: $e');
      }
    }
  }

  void _handleNewPlayerJoining(NodeJoinedEvent event) {
    // Only allow new players to join before game starts
    if (!_gameActive && isCoordinator) {
      appLog.info('New player joining before game start: ${event.nodeName}');
      // Auto-assign to a team (simple round-robin for now)
      final teamId =
          _playerAssignments.length % 2; // Alternate between team 0 and 1
      assignNodeToTeam(event.nodeId, teamId);
    }
  }

  void _updateNodeList() {
    if (_multiLayerCoordinator == null) return;

    _connectedNodes.clear();
    _connectedNodes.addAll(_multiLayerCoordinator!.knownNodes);

    // Add ourselves if not in the list
    final selfExists = _connectedNodes.any((node) => node.nodeId == _deviceId);
    if (!selfExists) {
      _connectedNodes.add(
        NetworkNode(
          nodeId: _deviceId!,
          nodeName: _deviceName!,
          role: _multiLayerCoordinator!.role,
          lastSeen: DateTime.now(),
          metadata: {},
        ),
      );
    }

    appLog.fine('Node list updated: ${_connectedNodes.length} nodes');
  }

  void _setupDefaultAssignments() {
    _playerAssignments[_deviceId!] = PlayerAssignment(
      nodeId: _deviceId!,
      nodeName: _deviceName!,
      teamId: 0,
      playerId: 'currentPlayer',
      isCoordinator: true,
    );
    appLog.info('Set up default coordinator assignment');
  }

  /// Assign a node to a team (coordinator only)
  void assignNodeToTeam(String nodeId, int teamId) {
    if (_networkingEnabled && !isCoordinator) {
      appLog.warning('Only coordinator can assign teams');
      return;
    }

    final node = _connectedNodes.firstWhere(
      (n) => n.nodeId == nodeId,
      orElse: () => throw ArgumentError('Node not found: $nodeId'),
    );

    _playerAssignments[nodeId] = PlayerAssignment(
      nodeId: nodeId,
      nodeName: node.nodeName,
      teamId: teamId,
      playerId: 'player_${nodeId.substring(0, 8)}',
      isCoordinator: nodeId == _deviceId,
    );

    if (_networkingEnabled) {
      _broadcastAssignments();
    }
    notifyListeners();
  }

  void _broadcastAssignments() {
    if (!isCoordinator || _multiLayerCoordinator == null) return;

    final assignmentData = {
      'assignments': _playerAssignments.map((k, v) => MapEntry(k, v.toMap())),
    };

    _multiLayerCoordinator!.sendApplicationMessage(
      'player_assignments',
      assignmentData,
    );
  }

  /// Send a game action over the network using the high-frequency game layer
  void sendGameAction(int teamId, String playerId, PaddleAction action) {
    if (!_networkingEnabled || _gameLayer == null || !_gameActive) {
      appLog.finest('Skipping game action: networking=$_networkingEnabled, gameActive=$_gameActive, layer=${_gameLayer != null}');
      return;
    }

    try {
      final playerIdHash = playerId.hashCode;
      final sample = [teamId, action.index, playerIdHash];

      _gameLayer!.sendData(sample);
      appLog.finest(
        'Sent game action: team=$teamId, player=$playerId, action=$action',
      );
    } catch (e) {
      appLog.warning('Failed to send game action: $e - This suggests the game layer is still a placeholder. MultiLayerCoordinator may need more time to establish full coordination.');
    }
  }

  /// Start the game (disable new peer discovery, enable game data layer)
  void startGame() {
    _gameActive = true;

    // Resume/unpause the game data layer
    if (_gameLayer != null) {
      _gameLayer!.resume();
      appLog.info('Game data layer resumed for active gameplay');
    }

    appLog.info(
      'Game started - peer discovery disabled, game data layer active',
    );
    notifyListeners();
  }

  /// Stop the game (re-enable peer discovery, pause game data layer)
  void stopGame() {
    _gameActive = false;

    // Pause the game data layer to save resources
    if (_gameLayer != null) {
      _gameLayer!.pause();
      appLog.info('Game data layer paused');
    }

    appLog.info(
      'Game stopped - peer discovery re-enabled, game data layer paused',
    );
    notifyListeners();
  }

  /// Check if we have enough players to start
  bool canStartGame() {
    return _playerAssignments.isNotEmpty;
  }

  /// Get game configuration
  Map<String, dynamic> getGameConfiguration() {
    return {
      'assignments': _playerAssignments.map((k, v) => MapEntry(k, v.toMap())),
      'coordinator': _deviceId,
      'gameMode': _networkingEnabled ? 'network' : 'local',
      'networkingEnabled': _networkingEnabled,
    };
  }

  /// Wait for nodes to join
  Future<List<NetworkNode>> waitForNodes(
    int minNodes, {
    Duration? timeout,
  }) async {
    if (!_networkingEnabled || _multiLayerCoordinator == null) {
      return _connectedNodes;
    }
    return await _multiLayerCoordinator!.waitForNodes(
      minNodes,
      timeout: timeout,
    );
  }

  /// Get coordinator node
  NetworkNode? getCoordinator() {
    if (!_networkingEnabled) {
      return _connectedNodes.isNotEmpty ? _connectedNodes.first : null;
    }

    final coordinatorId = _multiLayerCoordinator?.coordinatorId;
    if (coordinatorId == null) return null;

    return _connectedNodes.firstWhere(
      (node) => node.nodeId == coordinatorId,
      orElse: () => NetworkNode(
        nodeId: coordinatorId,
        nodeName: 'Coordinator',
        role: NodeRole.coordinator,
        lastSeen: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _gameDataSubscription?.cancel();
    _actionManager?.dispose();
    _multiLayerCoordinator?.dispose();
    _isInitialized = false;
    super.dispose();
  }
}
