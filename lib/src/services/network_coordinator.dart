import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:rise_together/src/services/net/network_config.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/settings/app_settings.dart';

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

/// Simplified network coordinator using LSLCoordinationSession
class NetworkCoordinator extends ChangeNotifier with AppLogging, AppSettings {
  LSLCoordinationSession? _session;
  StreamSubscription? _nodeJoinedSub;
  StreamSubscription? _nodeLeftSub;
  StreamSubscription? _userMessagesSub;
  StreamSubscription? _streamStartSub;
  StreamSubscription? _streamStopSub;
  StreamSubscription? _streamReadySub;
  LSLDataStream? _gameDataStream;
  LSLDataStream? _physDataStream;
  Timer? _statebroadcastTimer;
  static const int physicsBroadcastRate = 120; // Hz

  // Throttling for change-based physics updates
  DateTime? _lastPhysicsUpdate;
  static const int minPhysicsUpdateIntervalMs = 8; // ~120 FPS max

  // Physics state provider callback - will be set by the game
  List<double>? Function()? _gamePhysicsStateProvider;

  bool _isInitialized = false;
  bool _networkingEnabled = true;
  bool _gameActive = false;
  bool _gameStarting = false;
  bool _coordinatedStartInitiated = false;
  late String _deviceId;
  String? _deviceUId;
  String? _deviceName;
  DateTime? _scheduledStartTime;

  bool _inputAvailable = false;

  final Map<String, PlayerAssignment> _playerAssignments = {};
  final Set<String> _readyNodes = {};
  Map<String, dynamic>? _gameConfiguration;
  VoidCallback? _onGameStartCallback;
  void Function(List<double>)? _onPhysicsDataReceived;

  // Game action streaming
  final ActionStreamManager _actionManager;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isCoordinator => _session?.isCoordinator ?? false;
  bool get networkingEnabled => _networkingEnabled;
  bool get gameActive => _gameActive;
  bool get gameStarting => _gameStarting;
  String get deviceId {
    if (!_isInitialized) {
      throw StateError('NetworkCoordinator not initialized');
    }
    return _deviceId;
  }

  String? get deviceUId => _deviceUId;
  String? get deviceName => _deviceName;
  DateTime? get scheduledStartTime => _scheduledStartTime;
  Set<String> get readyNodes => Set.unmodifiable(_readyNodes);
  List<Node> get connectedNodes => _session?.connectedNodes ?? [];
  List<PlayerAssignment> get playerAssignments =>
      _playerAssignments.values.toList();
  PlayerAssignment get currentPlayerAssignment {
    if (!_isInitialized) {
      throw StateError('NetworkCoordinator not initialized');
    }
    final assignment = _playerAssignments[_deviceUId];
    if (assignment == null) {
      throw StateError('No player assignment for this device');
    }
    return assignment;
  }

  LSLCoordinationSession? get coordinationSession => _session;
  ActionStreamManager? get actionManager => _actionManager;
  Map<String, dynamic>? get gameConfiguration => _gameConfiguration;
  LSLDataStream? get physicsStateStream => _physDataStream;

  NetworkCoordinator(ActionStreamManager? actionManager)
    : _actionManager = actionManager ?? ActionStreamManager();

  /// Initialize with networking enabled/disabled
  Future<void> initialize({bool enableNetworking = true}) async {
    if (_isInitialized) return;

    // Web platform always uses local mode (no LSL networking)
    if (kIsWeb) {
      enableNetworking = false;
      appLog.info('Web platform detected - using local coordinator mode');
    }

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
      _deviceName = RiseTogetherNetworkConfig.generateDeviceName();
      _deviceId = RiseTogetherNetworkConfig.generateDeviceId();
      _deviceUId = RiseTogetherNetworkConfig.generateDeviceUId();
      final thisNodeConfig = NodeConfig(
        name: _deviceName!,
        id: _deviceId,
        uId: _deviceUId!,
        capabilities: {NodeCapability.coordinator, NodeCapability.participant},
      );

      // Create session configuration using the new simplified API
      final sessionConfig = CoordinationSessionConfig(
        name: 'rise_together_session',
        heartbeatInterval: Duration(seconds: 2),
        discoveryInterval: Duration(seconds: 5),
        nodeTimeout: Duration(seconds: 10),
        maxNodes: 8, // Allow up to 8 nodes
      );

      final coordinationConfig = CoordinationConfig(
        name: "RiseTogetherCoordination",
        sessionConfig: sessionConfig,
        topologyConfig: HierarchicalTopologyConfig(
          promotionStrategy: PromotionStrategyRandom(),
          maxNodes: 8,
        ),
        streamConfig: CoordinationStreamConfig(
          name: 'rise_together_coordination',
          sampleRate: 10.0,
        ),
        transportConfig: LSLTransportConfig(
          lslApiConfig: LSLApiConfig(
            ipv6: IPv6Mode.disable,
            logLevel: -2,
            portRange: 1024,
          ),
          coordinationFrequency: 10.0,
        ),
      );

      // Create and initialize session
      _session = LSLCoordinationSession(
        coordinationConfig,
        thisNodeConfig: thisNodeConfig,
      );
      await _session!.initialize();
      await _session!.join();

      _setupEventListeners();
      _setupGameActionManager();

      appLog.info(
        'NetworkCoordinator initialized - Role: ${isCoordinator ? "Coordinator" : "Participant"}',
      );

      // Set up default assignments if we're coordinator
      if (isCoordinator) {
        _setupDefaultAssignments();
      }
      _isInitialized = true;
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
    _playerAssignments[_deviceUId!] = PlayerAssignment(
      nodeId: _deviceId,
      nodeName: _deviceName!,
      teamId: 0,
      playerId: 'currentPlayer',
      isCoordinator: true,
    );

    appLog.info('NetworkCoordinator initialized in local mode');
  }

  void _setupGameActionManager() {
    // _actionManager = ActionStreamManager();
    appLog.info('Game action manager initialized');
  }

  void _setupEventListeners() {
    if (_session == null) return;

    // Listen for node topology changes
    if (isCoordinator) {
      _nodeJoinedSub = _session!.nodeJoined.listen((node) {
        appLog.info('Node joined: ${node.name} (${node.uId})');
        _handleNewPlayerJoining(node);
        notifyListeners();
      });

      _nodeLeftSub = _session!.nodeLeft.listen((node) {
        appLog.info('Node left: ${node.name} (${node.uId})');
        _playerAssignments.remove(node.uId);
        notifyListeners();
      });
    }

    // Listen for coordination messages
    _userMessagesSub = _session!.userMessages.listen((message) {
      appLog.info('Coordination message: ${message.messageId}');
      _handleCoordinationMessage(message);
    });

    // Listen for game data stream commands
    _streamStartSub = _session!.streamStartCommands.listen((command) async {
      appLog.info('PARTICIPANT: Stream start command: ${command.streamName}');
      if (command.streamName == 'GameData') {
        appLog.info('PARTICIPANT: Setting up game data stream...');
        _gameDataStream = await _session!.getDataStream('GameData');
        // Participant does not need to subscribe to inbox - coordinator handles that
        appLog.info(
          'PARTICIPANT: Game data stream created - should auto-send streamReady',
        );
      } else if (command.streamName == 'PhysicsState') {
        appLog.info(
          'PARTICIPANT: Setting up physics state stream reception...',
        );
        _physDataStream = await _session!.getDataStream('PhysicsState');
        appLog.info(
          'PARTICIPANT: Physics state stream created - should auto-send streamReady',
        );

        // Set up inbox listener and forward data directly to callback
        _physDataStream!.inbox.listen((message) {
          if (_onPhysicsDataReceived != null) {
            _onPhysicsDataReceived!(message.data.cast<double>());
          }
        });
        appLog.info(
          'PARTICIPANT: Physics state inbox listener set up - will forward to callback',
        );
      } else {
        appLog.info(
          'PARTICIPANT: Ignoring stream start for unknown stream: ${command.streamName}',
        );
      }
    });

    _streamStopSub = _session!.streamStopCommands.listen((command) {
      appLog.info('Stream stop command: ${command.streamName}');
      if (command.streamName == 'GameData') {
        _gameActive = false;
        _gameStarting = false;
      }
    });

    // Listen for stream ready notifications
    _streamReadySub = _session!.streamReadyNotifications.listen((
      notification,
    ) async {
      appLog.info(
        'Stream ready from node: ${notification.fromNodeUId} for stream: ${notification.streamName}',
      );
      appLog.info(
        'Is coordinator: $isCoordinator, Game starting: $_gameStarting',
      );

      if (notification.streamName == 'GameData') {
        appLog.info("GameData stream ready");
      } else if (notification.streamName == 'PhysicsState') {
        // Only handle stream ready from participants, not from coordinator itself
        if (notification.fromNodeUId != _session!.thisNode.uId) {
          _handleStreamReady(notification.fromNodeUId);
        }
        appLog.info(
          'PhysicsState stream is ready - participant can now receive physics updates',
        );
      } else {
        appLog.info(
          'Ignoring stream ready for unknown stream: ${notification.streamName}',
        );
      }
    });
  }

  Future<void> _handleCoordinationMessage(
    UserCoordinationMessage message,
  ) async {
    switch (message.messageId) {
      case 'player_assignments':
        if (!isCoordinator) {
          final assignmentsData =
              message.payload['assignments'] as Map<String, dynamic>?;
          final teamCountsData =
              message.payload['team_counts'] as Map<String, dynamic>?;

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

            // Store team player counts for game configuration
            if (teamCountsData != null) {
              final currentConfig = getEffectiveGameConfiguration();
              currentConfig['teams'] = Map<String, int>.from(teamCountsData);
              _gameConfiguration = currentConfig;
              appLog.info('Updated team player counts: $teamCountsData');
            }
            // Log each assignment for verification
            _playerAssignments.forEach((nodeId, assignment) {
              appLog.info(
                '  - Node $nodeId: Team ${assignment.teamId}, Player ${assignment.playerId}',
              );
              if (nodeId == _deviceId) {
                appLog.info(
                  '  >>> THIS IS MY ASSIGNMENT! Device $_deviceId assigned to Team ${assignment.teamId}',
                );
              }
            });
          }
        }
        break;
      case 'game_configuration':
        if (!isCoordinator) {
          final receivedConfig = Map<String, dynamic>.from(message.payload);
          // Apply config to appSettings
          if (receivedConfig.isEmpty) {
            appLog.warning(
              'Received null game configuration from coordinator - ignoring',
            );
            return;
          }
          appLog.info("Received game configuration: $receivedConfig");
          _gameConfiguration ??= getEffectiveGameConfiguration();
          for (final receivedSettings in receivedConfig.entries) {
            _gameConfiguration![receivedSettings.key] = receivedSettings.value;
            if (!appSettings.hasGroup(receivedSettings.key)) {
              appLog.warning(
                'Received unknown configuration group: ${receivedSettings.key} - ignoring',
              );
              continue;
            }
            final group = appSettings.getGroup(receivedSettings.key);
            appLog.info(
              'Applying configuration group: ${receivedSettings.key} with settings: ${receivedSettings.value}',
            );
            await group.updateFromMap(receivedSettings.value);
          }
          appLog.info('Received game configuration from coordinator');
          appLog.info(
            'Configuration keys: ${_gameConfiguration!.keys.toList()}',
          );
          notifyListeners();
        }
        break;
      case 'game_start_scheduled':
        if (!isCoordinator) {
          final startTimeStr = message.payload['start_time'] as String;
          _scheduledStartTime = DateTime.parse(startTimeStr);
          _gameStarting = true;
          appLog.info(
            'PARTICIPANT: Game start scheduled for: $_scheduledStartTime',
          );
          appLog.info('PARTICIPANT: Current time: ${DateTime.now()}');
          _scheduleGameStart();
          notifyListeners();
        } else {
          appLog.info(
            'COORDINATOR: Ignoring game_start_scheduled message (sent by self)',
          );
        }
        break;
      case 'start_game':
        if (!isCoordinator) {
          appLog.info(
            'PARTICIPANT: Game started by coordinator - transitioning to active state',
          );
          _gameActive = true;
          _gameStarting = false;

          appLog.info('PARTICIPANT: Triggering UI transition callback');

          // Trigger UI transition callback for participant
          _onGameStartCallback?.call();

          appLog.info('PARTICIPANT: UI transition callback called');
          notifyListeners();
        } else {
          appLog.info(
            'COORDINATOR: Ignoring start_game message (sent by self)',
          );
        }
        break;
      case 'stop_game':
        if (!isCoordinator) {
          appLog.info('Game stopped by coordinator');
          _gameActive = false;
          _gameStarting = false;
          _readyNodes.clear();
          notifyListeners();
        }
        break;
    }
  }

  Future<void> _setupGameDataStream() async {
    if (!isCoordinator) return;
    if (_session == null || _gameDataStream != null) return;

    final streamConfig = DataStreamConfig(
      name: 'GameData',
      channels: 3, // teamId, actionIndex, playerIdHash
      sampleRate: 120.0,
      dataType: StreamDataType.int32,
      participationMode: StreamParticipationMode.sendAllReceiveCoordinator,
    );
    appLog.info('Creating game data stream...');
    _gameDataStream = await _session!.createDataStream(streamConfig);

    // Listen for incoming game actions
    _gameDataStream!.inbox.listen((message) {
      if (!_gameActive) {
        return;
      }

      try {
        message = message as Int32Message;
        final teamId = message.data[0];
        final actionIndex = message.data[1];
        final playerIdHash = message.data[2];

        if (actionIndex >= 0 && actionIndex < PaddleAction.values.length) {
          final action = PaddleAction.values[actionIndex];
          final playerId = 'remote_player_$playerIdHash';

          final teamStream = _actionManager.getTeamStream(teamId);
          if (teamStream != null) {
            teamStream.addAction(GameAction(playerId, action));
          }

          appLog.logData(
            'app_data',
            'GAME_ACTION_RECEIVED',
            data: {
              'inlet_timestamp': message.timestamp,
              'lsl_timestamp': message.getMetadata(
                'lsl_timestamp',
                defaultValue: null,
              ),
              'processed_timestamp': message.getMetadata(
                'received_at',
                defaultValue: null,
              ),
              'lsl_time_correction': message.getMetadata(
                'lsl_time_correction',
                defaultValue: null,
              ),
              'team_id': teamId,
              'action_index': actionIndex,
              'player_id_hash': playerIdHash,
              'action': action.toString(),
              'player_id': playerId,
            },
            timestamp: DateTime.now(),
          );
        }
      } catch (e) {
        appLog.warning('Error processing game data: $e');
      }
    });

    appLog.info('Game data stream created and ready');
  }

  Future<void> processPendingInputs() async {
    if (!_inputAvailable || _gameDataStream == null) {
      return;
    }
  }

  void _handleNewPlayerJoining(Node node) {
    // Only allow new players to join before game starts
    if (!_gameActive && !_gameStarting && isCoordinator) {
      appLog.info('New player joining before game start: ${node.name}');

      // Auto-assign to the team with fewer players (better team balance)
      final teamCounts = <int, int>{0: 0, 1: 0};
      for (final assignment in _playerAssignments.values) {
        teamCounts[assignment.teamId] =
            (teamCounts[assignment.teamId] ?? 0) + 1;
      }

      // Assign to the team with fewer players
      final teamId = (teamCounts[0]! <= teamCounts[1]!) ? 0 : 1;

      appLog.info(
        'Team counts - Team 0: ${teamCounts[0]}, Team 1: ${teamCounts[1]}',
      );
      appLog.info('Assigning ${node.name} to team $teamId');

      assignNodeToTeam(node.uId, teamId);
    }
  }

  void _handleStreamReady(String nodeUId) {
    _readyNodes.add(nodeUId);
    appLog.info(
      'Node $nodeUId is ready. Ready nodes: ${_readyNodes.length}/${connectedNodes.length}',
    );
    appLog.info('Ready node IDs: ${_readyNodes.toList()}');
    appLog.info(
      'Connected node IDs: ${connectedNodes.map((n) => n.uId).toList()}',
    );

    if (isCoordinator && _gameStarting) {
      // Check if all connected nodes are ready
      final allNodesReady = connectedNodes.every(
        (node) => _readyNodes.contains(node.uId),
      );
      appLog.info('All nodes ready check: $allNodesReady');

      if (allNodesReady && !_coordinatedStartInitiated) {
        appLog.info('All nodes are ready! Starting coordinated game start.');
        _coordinatedStartInitiated = true;
        _initiateCoordinatedStart();
      } else {
        // Debug which nodes are missing
        final missingNodes = connectedNodes
            .where((node) => !_readyNodes.contains(node.uId))
            .map((node) => '${node.name} (${node.uId})')
            .toList();
        appLog.info('Still waiting for nodes: $missingNodes');
      }
    }

    notifyListeners();
  }

  Future<void> _setupPhysicsStateStream() async {
    if (!isCoordinator || _session == null || _physDataStream != null) return;

    final streamConfig = DataStreamConfig(
      name: 'PhysicsState',
      channels:
          14, // Team1: ballX, ballY, paddleY, paddleAngle, stateL, stateR + Team2: ballX, ballY, paddleY, paddleAngle, stateL, stateR
      sampleRate: physicsBroadcastRate.toDouble(),
      dataType: StreamDataType.float32,
      participationMode: StreamParticipationMode.coordinatorOnly,
    );

    _physDataStream = await _session!.createDataStream(streamConfig);
    appLog.info('Physics state stream created for coordinator');
  }

  void _broadcastPhysicsState() {
    if (!isCoordinator) {
      appLog.warning('Physics broadcast called on non-coordinator');
      return;
    }
    if (_physDataStream == null) {
      appLog.warning('Physics broadcast called but stream is null');
      return;
    }
    if (_gamePhysicsStateProvider == null) {
      appLog.warning('Physics broadcast called but provider is null');
      return;
    }

    // Get current physics state from the game
    final state = _gamePhysicsStateProvider!();
    if (state != null) {
      appLog.logData(
        'app_data',
        'PHYSICS_STATE_BROADCAST',
        data: {'state': state},
        timestamp: DateTime.now(),
      );
      _physDataStream!.sendData(state);
      // Debug log occasionally to verify data is being sent
      // if (DateTime.now().millisecondsSinceEpoch % 1000 < 50) {
      //   appLog.info(
      //     'Coordinator sent physics state: ballPos=(${state[0].toStringAsFixed(2)}, ${state[1].toStringAsFixed(2)}), paddleY=${state[2].toStringAsFixed(2)}',
      //   );
      // }
    } else {
      appLog.warning('Physics state provider returned null');
    }
  }

  /// Broadcast physics state on demand (with throttling)
  void broadcastPhysicsStateOnChange() {
    if (!_gameActive || !isCoordinator) return;

    final now = DateTime.now();
    if (_lastPhysicsUpdate != null) {
      final timeSinceLastUpdate = now
          .difference(_lastPhysicsUpdate!)
          .inMilliseconds;
      if (timeSinceLastUpdate < minPhysicsUpdateIntervalMs) {
        return; // Too soon, skip this update
      }
    }

    _lastPhysicsUpdate = now;
    _broadcastPhysicsState();
  }

  void _initiateCoordinatedStart() async {
    await _session!.startStream('GameData');
    await _session!.startStream('PhysicsState');
    // Schedule game start 5 seconds in the future
    _scheduledStartTime = DateTime.now().add(Duration(seconds: 5));
    _gameStarting = true;

    // Notify all participants of the scheduled start time
    _session!.sendUserMessage(
      'game_start_scheduled',
      'Game will start at scheduled time',
      {'start_time': _scheduledStartTime!.toIso8601String()},
    );

    appLog.info('Coordinated game start scheduled for: $_scheduledStartTime');
    _scheduleGameStart();
    notifyListeners();
  }

  void _scheduleGameStart() {
    if (_scheduledStartTime == null) return;

    final delay = _scheduledStartTime!.difference(DateTime.now());
    if (delay.isNegative) {
      // Start immediately if we're past the scheduled time
      _actuallyStartGame();
    } else {
      // Schedule the start
      Timer(delay, _actuallyStartGame);
      appLog.info('Game will start in ${delay.inSeconds} seconds');
    }
  }

  void _actuallyStartGame() {
    _gameActive = true;
    _gameStarting = false;

    if (isCoordinator) {
      // Physics state will now be broadcast on-demand when changes occur
      // No more periodic timer needed

      // Send final start message
      _session!.sendUserMessage('start_game', 'Game started now!', {});
    }

    appLog.info('Game has started! Triggering UI transition.');

    // Trigger UI transition callback
    _onGameStartCallback?.call();

    notifyListeners();
  }

  void _setupDefaultAssignments() {
    _playerAssignments[_deviceUId!] = PlayerAssignment(
      nodeId: _deviceId,
      nodeName: _deviceName!,
      teamId: 0,
      playerId: 'currentPlayer',
      isCoordinator: true,
    );
    appLog.info(
      'Coordinator: Set up default assignment - Team 0, Player: currentPlayer, Node: $_deviceId',
    );
  }

  /// Assign a node to a team (coordinator only)
  Future<void> assignNodeToTeam(String nodeId, int teamId) async {
    if (_networkingEnabled && !isCoordinator) {
      appLog.warning('Only coordinator can assign teams');
      return;
    }

    final node = connectedNodes.firstWhere(
      (n) => n.uId == nodeId,
      orElse: () => throw ArgumentError('Node not found: $nodeId'),
    );

    _playerAssignments[nodeId] = PlayerAssignment(
      nodeId: nodeId,
      nodeName: node.name,
      teamId: teamId,
      playerId: 'player_${nodeId.substring(0, 8)}',
      isCoordinator: nodeId == _deviceId,
    );

    appLog.info(
      'Coordinator: Assigned node $nodeId (${node.name}) to team $teamId',
    );

    if (_networkingEnabled) {
      await _broadcastAssignments();
    }
    notifyListeners();
  }

  /// Unassign a node from any team (coordinator only)
  Future<void> unassignNode(String nodeId) async {
    if (_networkingEnabled && !isCoordinator) {
      appLog.warning('Only coordinator can unassign teams');
      return;
    }

    if (_playerAssignments.containsKey(nodeId)) {
      final assignment = _playerAssignments[nodeId]!;
      _playerAssignments.remove(nodeId);

      appLog.info(
        'Coordinator: Unassigned node $nodeId (${assignment.nodeName}) from team ${assignment.teamId}',
      );

      if (_networkingEnabled) {
        await _broadcastAssignments();
      }
      notifyListeners();
    }
  }

  Future<void> _broadcastAssignments() async {
    if (!isCoordinator || _session == null) return;

    // Calculate team player counts
    final teamCounts = <String, int>{};
    for (final assignment in _playerAssignments.values) {
      final teamKey = assignment.teamId.toString();
      teamCounts[teamKey] = (teamCounts[teamKey] ?? 0) + 1;
    }

    final assignmentData = {
      'assignments': _playerAssignments.map((k, v) => MapEntry(k, v.toMap())),
      'team_counts': teamCounts,
    };

    await _session!.sendUserMessage(
      'player_assignments',
      'Player team assignments update',
      assignmentData,
    );

    // Also update coordinator's own game configuration with team counts
    final currentConfig = _gameConfiguration ?? <String, dynamic>{};
    currentConfig['teams'] = teamCounts;
    _gameConfiguration = currentConfig;

    appLog.info(
      'Broadcasted player assignments to ${connectedNodes.length} participants',
    );
    appLog.info('Updated coordinator team player counts: $teamCounts');

    // Log assignments being sent for verification
    _playerAssignments.forEach((nodeId, assignment) {
      appLog.info(
        '  - Broadcasting: Node $nodeId → Team ${assignment.teamId}, Player ${assignment.playerId}',
      );
    });
  }

  /// Set and broadcast game configuration (coordinator only)
  void setGameConfiguration(Map<String, dynamic> config) {
    if (!isCoordinator) {
      appLog.warning('Only coordinator can set game configuration');
      return;
    }

    // Store the configuration locally
    _gameConfiguration = Map<String, dynamic>.from(config);
    _gameConfiguration = getEffectiveGameConfiguration();
    appLog.info('Game configuration set: ${config.keys.toList()}');

    // Broadcast to all participants if networking is enabled
    if (_networkingEnabled && _session != null) {
      _session!.sendUserMessage(
        'game_configuration',
        'Game configuration from coordinator',
        _gameConfiguration!,
      );
      appLog.info(
        'Broadcasted game configuration to ${connectedNodes.length} participants',
      );
    }

    notifyListeners();
  }

  /// Get the current game configuration with fallbacks
  Map<String, dynamic> getEffectiveGameConfiguration() {
    // Always start with default configuration to ensure all settings groups are included
    final defaultConfig = getDefaultGameConfiguration();

    // If we have received/set configuration, merge it with defaults
    if (_gameConfiguration != null) {
      final mergedConfig = Map<String, dynamic>.from(defaultConfig);
      // Override with any explicitly set configuration
      for (final entry in _gameConfiguration!.entries) {
        mergedConfig[entry.key] = entry.value;
      }
      print('Effective game configuration: $mergedConfig');
      return mergedConfig;
    }
    // Use default configuration
    print('Using default game configuration: $defaultConfig');
    return defaultConfig;
  }

  /// Get team player counts for thrust calculation
  Map<String, int> _getTeamPlayerCounts() {
    final teamCounts = <String, int>{};

    // Count players assigned to each team
    for (final assignment in _playerAssignments.values) {
      final teamKey = assignment.teamId.toString();
      teamCounts[teamKey] = (teamCounts[teamKey] ?? 0) + 1;
    }

    return teamCounts;
  }

  /// Get default game configuration
  Map<String, dynamic> getDefaultGameConfiguration() {
    // Get current settings as base, but override specific values for participants
    final config = <String, dynamic>{};

    // Export game settings with debug_mode disabled for participants
    final gameSettings = appSettings.getGroup('game').toMap();
    gameSettings['debug_mode'] = false; // Disable DEMO MODE for participants
    config['game'] = gameSettings;

    // Export colors and physics settings as-is
    config['colors'] = appSettings.getGroup('colors').toMap();
    final physicsSettings = appSettings.getGroup('physics').toMap();
    config['physics'] = physicsSettings;
    config['network'] = appSettings.getGroup('network').toMap();

    // Add coordinator-specific info (device info from device group)
    final deviceSettings = appSettings.getGroup('device').toMap();
    config['coordinator'] = {
      'device_id': deviceSettings['device_id'] ?? _deviceId,
      'device_name': deviceSettings['device_name'] ?? _deviceName,
    };
    config['session'] = {
      'session_id': 'rise_together_${DateTime.now().millisecondsSinceEpoch}',
      'created_at': DateTime.now().toIso8601String(),
      'networking_enabled': _networkingEnabled,
    };

    // Add team player counts for thrust calculation
    config['teams'] = _getTeamPlayerCounts();

    return config;
  }

  /// Send a game action over the network using the game data stream
  void sendGameAction(int teamId, String playerId, PaddleAction action) {
    if (!_networkingEnabled || !_gameActive || _gameDataStream == null) {
      appLog.finest(
        'Skipping game action: networking=$_networkingEnabled, gameActive=$_gameActive, stream=${_gameDataStream != null}',
      );
      return;
    }

    try {
      final playerIdHash = playerId.hashCode;
      final sample = [teamId, action.index, playerIdHash];

      _gameDataStream!.sendData(sample);
      appLog.logData(
        'app_data',
        'GAME_ACTION_SENT',
        data: {
          'team_id': teamId,
          'action_index': action.index,
          'player_id_hash': playerIdHash,
          'action': action.toString(),
          'player_id': playerId,
        },
        timestamp: DateTime.now(),
      );
    } catch (e) {
      appLog.warning('Failed to send game action: $e');
    }
  }

  /// Start the game (coordinator initiates coordinated start)
  Future<void> startGame() async {
    if (!isCoordinator) {
      appLog.warning('Only coordinator can start the game');
      return;
    }

    // Set up default game configuration if none exists
    _gameConfiguration = getEffectiveGameConfiguration();

    // Broadcast current game configuration and team assignments
    if (_networkingEnabled && _session != null) {
      // Send configuration
      await _session!.sendUserMessage(
        'game_configuration',
        'Game configuration from coordinator',
        _gameConfiguration!,
      );

      // Ensure team assignments are also broadcasted
      await _broadcastAssignments();

      appLog.info('Broadcasted configuration and assignments to participants');

      // Give participants a moment to receive configuration
      await Future.delayed(Duration(milliseconds: 500));

      // Validate sync status before proceeding
      validateSync();
    }

    _gameStarting = true;
    _coordinatedStartInitiated = false;
    _readyNodes.clear();

    // Create and start the game data stream
    if (_gameDataStream == null) {
      await _setupGameDataStream();
    }

    if (_physDataStream == null) {
      await _setupPhysicsStateStream();
    }

    // Add coordinator as ready immediately
    _readyNodes.add(_session!.thisNode.uId);

    // Debug logging
    appLog.info('Connected nodes count: ${connectedNodes.length}');
    appLog.info(
      'Connected node IDs: ${connectedNodes.map((n) => '${n.name}(${n.uId.substring(0, 8)})').join(', ')}',
    );
    appLog.info(
      'Ready nodes: ${_readyNodes.length} - ${_readyNodes.map((id) => id.substring(0, 8)).join(', ')}',
    );

    // Check if we're the only node (single player or web)
    if (connectedNodes.length <= 1) {
      appLog.info('Single player mode - starting immediately');
      _session!.startStream('GameData');
      _session!.startStream('PhysicsState');
      _actuallyStartGame();
    } else {
      appLog.info(
        'Multiplayer mode - waiting for ${connectedNodes.length} nodes to be ready',
      );
      appLog.info('Will start when all nodes send streamReady notifications');

      // Check if somehow all nodes are already ready (shouldn't happen but let's be safe)
      final allNodesReady = connectedNodes.every(
        (node) => _readyNodes.contains(node.uId),
      );
      if (allNodesReady) {
        appLog.warning(
          'All nodes already ready - this is unexpected, but starting coordinated sequence',
        );
        _initiateCoordinatedStart();
      }
    }

    notifyListeners();
  }

  /// Stop the game
  Future<void> stopGame() async {
    _gameActive = false;

    if (isCoordinator) {
      // Coordinator stops the game data stream and notifies participants
      await _session!.stopStream('GameData');
      await _session!.stopStream('PhysicsState');
      await _session!.sendUserMessage(
        'stop_game',
        'Game stopped by coordinator',
        {},
      );
      appLog.info('Game stopped and participants notified');
    } else {
      appLog.info('Game marked as inactive');
    }

    notifyListeners();
  }

  /// Check if we have enough players to start
  bool canStartGame() {
    return _playerAssignments.isNotEmpty;
  }

  /// Get game configuration (legacy method - now uses new system)
  Map<String, dynamic> getGameConfiguration() {
    final config = getEffectiveGameConfiguration();

    // Add runtime information
    config['assignments'] = _playerAssignments.map(
      (k, v) => MapEntry(k, v.toMap()),
    );
    config['coordinator'] = _deviceId;
    config['gameMode'] = _networkingEnabled ? 'network' : 'local';
    config['networkingEnabled'] = _networkingEnabled;
    config['connectedNodes'] = connectedNodes.length;
    config['gameActive'] = _gameActive;
    config['gameStarting'] = _gameStarting;

    return config;
  }

  /// Validate that configuration and assignments are properly synced
  Map<String, dynamic> validateSync() {
    final status = <String, dynamic>{};

    // Check configuration sync
    status['configurationSynced'] = _gameConfiguration != null;
    status['assignmentCount'] = _playerAssignments.length;
    status['connectedNodeCount'] = connectedNodes.length;

    // Check if all connected nodes have assignments
    final assignedNodes = _playerAssignments.keys.toSet();
    final connectedNodeIds = connectedNodes.map((n) => n.uId).toSet();
    final unassignedNodes = connectedNodeIds.difference(assignedNodes);

    status['allNodesAssigned'] = unassignedNodes.isEmpty;
    status['unassignedNodes'] = unassignedNodes.toList();

    // Team distribution
    final teamCounts = <int, int>{};
    for (final assignment in _playerAssignments.values) {
      teamCounts[assignment.teamId] = (teamCounts[assignment.teamId] ?? 0) + 1;
    }
    status['teamDistribution'] = teamCounts;

    // Log validation results
    appLog.info('=== SYNC VALIDATION ===');
    appLog.info('Configuration synced: ${status['configurationSynced']}');
    appLog.info(
      'Assignments: ${status['assignmentCount']}/${status['connectedNodeCount']} nodes',
    );
    appLog.info('All nodes assigned: ${status['allNodesAssigned']}');
    appLog.info('Team distribution: ${status['teamDistribution']}');
    if (unassignedNodes.isNotEmpty) {
      appLog.warning('Unassigned nodes: $unassignedNodes');
    }
    appLog.info('=======================');

    return status;
  }

  /// Set callback to be called when game actually starts
  void setOnGameStartCallback(VoidCallback callback) {
    _onGameStartCallback = callback;
  }

  /// Set callback to be called when physics data is received (participant only)
  void setOnPhysicsDataReceivedCallback(void Function(List<double>) callback) {
    _onPhysicsDataReceived = callback;
  }

  /// Set the physics state provider callback (coordinator only)
  void setPhysicsStateProvider(List<double>? Function() provider) {
    if (!isCoordinator) {
      appLog.warning('Only coordinator can set physics state provider');
      return;
    }
    _gamePhysicsStateProvider = provider;
    appLog.info('Physics state provider set for coordinator');
  }

  /// Start physics state broadcasting (coordinator only)
  Future<void> startPhysicsStateBroadcast() async {
    if (!isCoordinator) {
      appLog.warning('Only coordinator can start physics state broadcast');
      return;
    }

    if (_physDataStream == null) {
      await _setupPhysicsStateStream();
    }

    appLog.info('Physics state broadcast started');
  }

  /// Stop physics state broadcasting
  void stopPhysicsStateBroadcast() {
    _statebroadcastTimer?.cancel();
    _statebroadcastTimer = null;
    appLog.info('Physics state broadcast stopped');
  }

  @override
  void dispose() {
    _nodeJoinedSub?.cancel();
    _nodeLeftSub?.cancel();
    _userMessagesSub?.cancel();
    _streamStartSub?.cancel();
    _streamReadySub?.cancel();
    _streamStopSub?.cancel();
    _statebroadcastTimer?.cancel();
    // _actionManager?.dispose();
    _session?.dispose();
    _isInitialized = false;
    super.dispose();
  }
}
