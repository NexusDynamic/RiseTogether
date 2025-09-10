import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/services/net/network_bridge.dart';
import 'package:rise_together/src/services/network_coordinator.dart';

/// Provides action system and network bridge for the game
/// Abstracts away networking details from the game class
abstract class ActionProvider {
  ActionStreamManager get actionManager;
  NetworkBridge get networkBridge;

  /// Initialize the action provider and start consuming streams
  Future<void> initialize();

  /// Start gameplay mode (coordinator sends start signal)
  Future<void> startGameplay();

  /// Stop gameplay mode (coordinator sends stop signal)
  Future<void> stopGameplay();

  /// Check if this node is the coordinator
  bool get isCoordinator;

  /// Get the current player's team assignment
  PlayerAssignment get currentPlayerAssignment;

  /// Get all player assignments
  List<PlayerAssignment> get playerAssignments;

  /// Dispose resources
  void dispose();
}

/// Local action provider - no networking, single player
class LocalActionProvider implements ActionProvider {
  final ActionStreamManager _actionManager;
  late final NetworkBridge _networkBridge;

  @override
  ActionStreamManager get actionManager => _actionManager;

  @override
  NetworkBridge get networkBridge => _networkBridge;

  @override
  bool get isCoordinator => true; // Always coordinator in local mode

  @override
  PlayerAssignment get currentPlayerAssignment => PlayerAssignment(
    nodeId: 'local',
    nodeName: 'Local Player',
    teamId: 0, // Default to team 0 for local mode
    playerId: 'local_player',
    isCoordinator: true,
  );

  @override
  List<PlayerAssignment> get playerAssignments => [currentPlayerAssignment];

  LocalActionProvider(ActionStreamManager? actionManager)
    : _actionManager = actionManager ?? ActionStreamManager();

  @override
  Future<void> initialize() async {
    _networkBridge = NetworkBridge(_actionManager, useLocalNetwork: true);
    await _networkBridge.initialize();
  }

  @override
  Future<void> startGameplay() async {
    // Nothing special needed for local mode
  }

  @override
  Future<void> stopGameplay() async {
    // Nothing special needed for local mode
  }

  @override
  void dispose() {
    _networkBridge.dispose();
  }
}

/// Network action provider - consumes LSL streams directly
/// Coordinator nodes can also be players
class NetworkActionProvider implements ActionProvider {
  final NetworkCoordinator _networkCoordinator;

  /// Get the underlying network coordinator
  NetworkCoordinator get networkCoordinator => _networkCoordinator;
  late final NetworkBridge _networkBridge;

  NetworkActionProvider(this._networkCoordinator);

  @override
  ActionStreamManager get actionManager => _networkCoordinator.actionManager!;

  @override
  NetworkBridge get networkBridge => _networkBridge;

  @override
  bool get isCoordinator => _networkCoordinator.isCoordinator;

  @override
  PlayerAssignment get currentPlayerAssignment =>
      _networkCoordinator.currentPlayerAssignment;

  @override
  List<PlayerAssignment> get playerAssignments =>
      _networkCoordinator.playerAssignments;

  @override
  Future<void> initialize() async {
    // ActionManager from coordinator already consuming all LSL action streams
    // NetworkBridge handles local player's action publishing
    _networkBridge = NetworkBridge(
      _networkCoordinator.actionManager!,
      useLocalNetwork: false,
      networkCoordinator: _networkCoordinator,
    );
    await _networkBridge.initialize();
  }

  @override
  Future<void> startGameplay() async {
    // Only coordinator can start the game
    if (isCoordinator) {
      await _networkCoordinator.startGame();
    }
    // All nodes (including coordinator) participate as players
  }

  @override
  Future<void> stopGameplay() async {
    // Only coordinator can stop the game
    if (isCoordinator) {
      await _networkCoordinator.stopGame();
    }
  }

  @override
  void dispose() {
    _networkBridge.dispose();
  }
}
