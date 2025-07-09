import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:rise_together/src/services/net/network_config.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/net/native/network_action_bridge.dart';
import 'package:rise_together/src/game/action_system.dart';

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

/// Manages network coordination and player assignments in the menu phase
class CoordinationManager extends ChangeNotifier with AppLogging {
  LSLCoordinationNode? _coordinationNode;
  StreamSubscription? _eventSubscription;

  bool _isInitialized = false;
  bool _isCoordinator = false;
  String? _deviceId;
  String? _deviceName;

  final List<NetworkNode> _connectedNodes = [];
  final Map<String, PlayerAssignment> _playerAssignments = {};

  // Game transport layer - established immediately after coordination
  NetworkActionBridge? _gameTransport;
  ActionStreamManager? _gameActionManager;
  bool _gameTransportInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isCoordinator => _isCoordinator;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  List<NetworkNode> get connectedNodes => List.unmodifiable(_connectedNodes);
  List<PlayerAssignment> get playerAssignments =>
      _playerAssignments.values.toList();

  /// Get the coordination node (for reusing in other components)
  LSLCoordinationNode? get coordinationNode => _coordinationNode;

  /// Get the game transport bridge (for reusing in game components)
  NetworkActionBridge? get gameTransport => _gameTransport;

  /// Get the game action manager (for reusing in game components)
  ActionStreamManager? get gameActionManager => _gameActionManager;

  /// Check if game transport is initialized
  bool get isGameTransportInitialized => _gameTransportInitialized;

  /// Initialize coordination network (call this in menu)
  Future<void> initialize() async {
    if (_isInitialized) return;

    appLog.info('Initializing CoordinationManager');

    try {
      _deviceId = RiseTogetherNetworkConfig.generateDeviceId();
      _deviceName = RiseTogetherNetworkConfig.generateDeviceName();

      _coordinationNode = LSLCoordinationNode(
        nodeId: _deviceId!,
        nodeName: _deviceName!,
        streamName: 'risetogether_coordination',
        config: RiseTogetherNetworkConfig.createCoordinationConfig(),
      );

      await _coordinationNode!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Coordination node initialization timed out');
        },
      );

      await _coordinationNode!.join().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Coordination node join timed out');
        },
      );

      _setupEventListeners();

      // Wait a brief moment to discover existing coordinator, but don't hang forever
      await Future.delayed(const Duration(seconds: 1));

      _isCoordinator = _coordinationNode!.role == NodeRole.coordinator;
      _isInitialized = true;

      appLog.info(
        'CoordinationManager initialized - Role: ${_coordinationNode!.role}',
      );

      // If we're the coordinator, set up default assignments
      if (_isCoordinator) {
        _setupDefaultAssignments();
      }

      notifyListeners();
    } catch (e) {
      appLog.severe('Failed to initialize CoordinationManager: $e');
      rethrow;
    }
  }

  void _setupEventListeners() {
    if (_coordinationNode == null) return;

    _eventSubscription = _coordinationNode!.eventStream.listen((event) {
      appLog.info('Coordination event: ${event.runtimeType}');

      // Handle specific coordination events
      switch (event) {
        case TopologyChangedEvent():
          _updateNodeList();
          break;
        case RoleChangedEvent():
          _isCoordinator = _coordinationNode!.role == NodeRole.coordinator;
          if (_isCoordinator) {
            _setupDefaultAssignments();
          }
          break;
        case ApplicationEvent():
          _handleApplicationEvent(event);
          break;
        case NodeJoinedEvent():
          _updateNodeList();
          break;
        case NodeLeftEvent():
          appLog.warning(
            'NodeLeftEvent detected - current device ID: $_deviceId',
          );
          appLog.warning(
            'Known nodes before update: ${_connectedNodes.map((n) => '${n.nodeName}(${n.nodeId.substring(0, 12)})').join(', ')}',
          );
          _updateNodeList();
          appLog.warning(
            'Known nodes after update: ${_connectedNodes.map((n) => '${n.nodeName}(${n.nodeId.substring(0, 12)})').join(', ')}',
          );
          break;
      }

      notifyListeners();
    });
  }

  void _handleApplicationEvent(ApplicationEvent event) {
    appLog.info('Application event: ${event.type}');

    switch (event.type) {
      case 'player_assignments':
        if (!_isCoordinator) {
          // Receive assignments from coordinator
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
    }
  }

  void _updateNodeList() {
    if (_coordinationNode == null) return;

    appLog.fine('_updateNodeList called:');
    appLog.fine('  Our device ID: $_deviceId');
    appLog.fine(
      '  Known nodes from coordination: ${_coordinationNode!.knownNodes.map((n) => '${n.nodeName}(${n.nodeId})').join(', ')}',
    );

    _connectedNodes.clear();
    _connectedNodes.addAll(_coordinationNode!.knownNodes);

    // Add ourselves if not already in the list
    final selfExists = _connectedNodes.any((node) => node.nodeId == _deviceId);
    appLog.fine('  Self exists in known nodes: $selfExists');

    if (!selfExists) {
      appLog.fine('  Adding self to node list');
      _connectedNodes.add(
        NetworkNode(
          nodeId: _deviceId!,
          nodeName: _deviceName!,
          role: _coordinationNode!.role,
          lastSeen: DateTime.now(),
          metadata: {},
        ),
      );
    }

    appLog.fine(
      '  Final node list: ${_connectedNodes.map((n) => '${n.nodeName}(${n.nodeId})').join(', ')}',
    );

    // Establish game transport layer immediately after node discovery
    _ensureGameTransportInitialized();
  }

  void _setupDefaultAssignments() {
    // Assign coordinator to team 0 by default
    _playerAssignments[_deviceId!] = PlayerAssignment(
      nodeId: _deviceId!,
      nodeName: _deviceName!,
      teamId: 0,
      playerId: 'currentPlayer',
      isCoordinator: true,
    );
  }

  /// Assign a node to a team (coordinator only)
  void assignNodeToTeam(String nodeId, int teamId) {
    if (!_isCoordinator) {
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

    // Broadcast assignment to all nodes
    _broadcastAssignments();
    notifyListeners();
  }

  void _broadcastAssignments() {
    if (!_isCoordinator || _coordinationNode == null) return;

    final assignmentData = {
      'assignments': _playerAssignments.map((k, v) => MapEntry(k, v.toMap())),
    };

    _coordinationNode!.sendApplicationMessage(
      'player_assignments',
      assignmentData,
    );
  }

  /// Get current game configuration (team assignments, etc.)
  Map<String, dynamic> getGameConfiguration() {
    return {
      'assignments': _playerAssignments.map((k, v) => MapEntry(k, v.toMap())),
      'coordinator': _deviceId,
      'gameMode': 'network',
    };
  }

  /// Check if we have enough players to start the game
  bool canStartGame() {
    return _playerAssignments.isNotEmpty;
  }

  /// Wait for a specific number of nodes to join
  Future<List<NetworkNode>> waitForNodes(
    int minNodes, {
    Duration? timeout,
  }) async {
    if (_coordinationNode == null) {
      throw StateError('Coordination node not initialized');
    }
    return await _coordinationNode!.waitForNodes(minNodes, timeout: timeout);
  }

  /// Wait for this node to become coordinator
  Future<void> waitForCoordinator({Duration? timeout}) async {
    if (_coordinationNode == null) {
      throw StateError('Coordination node not initialized');
    }
    await _coordinationNode!.waitForRole(
      NodeRole.coordinator,
      timeout: timeout,
    );
  }

  /// Get the current coordinator node
  NetworkNode? getCoordinator() {
    final coordinatorId = _coordinationNode?.coordinatorId;
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

  /// Initialize game transport layer (called immediately after coordination setup)
  Future<void> _ensureGameTransportInitialized() async {
    if (_gameTransportInitialized || _coordinationNode == null) return;

    appLog.info('Initializing game transport layer during coordination phase');

    try {
      // Create action manager if not exists
      _gameActionManager ??= ActionStreamManager();

      // Create game transport bridge
      _gameTransport = NetworkActionBridge(
        actionManager: _gameActionManager!,
        deviceId: _deviceId,
        deviceName: _deviceName,
        performancePreset: PerformancePreset.balanced,
        coordinationManager: this,
      );

      // Initialize with paused mode (low frequency, no busy wait)
      await _gameTransport!.initializePausedMode();

      _gameTransportInitialized = true;
      appLog.info('Game transport layer initialized in paused mode');
    } catch (e) {
      appLog.severe('Failed to initialize game transport layer: $e');
      // Don't rethrow - coordination should continue even if game transport fails
    }
  }

  /// Activate full game transport (called when game starts)
  Future<void> activateGameTransport() async {
    if (!_gameTransportInitialized || _gameTransport == null) {
      appLog.warning('Game transport not initialized, initializing now');
      await _ensureGameTransportInitialized();
    }

    if (_gameTransport != null) {
      appLog.info('Activating full game transport (busy-wait mode)');
      await _gameTransport!.activateFullMode();
    }
  }

  /// Deactivate game transport (pause busy-wait polling)
  Future<void> pauseGameTransport() async {
    if (_gameTransport != null) {
      appLog.info('Pausing game transport (returning to low-frequency mode)');
      await _gameTransport!.pauseMode();
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _gameTransport?.dispose();
    _gameActionManager?.dispose();
    _coordinationNode?.dispose();
    _isInitialized = false;
    super.dispose();
  }
}
