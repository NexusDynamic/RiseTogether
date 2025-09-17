import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/services/net/network_bridge.dart';
import 'package:rise_together/src/services/network_coordinator.dart';

/// Provides action system and network bridge for the game
/// Abstracts away networking details from the game class
abstract class ActionProvider {
  ActionStreamManager get actionManager;
  NetworkBridge get networkBridge;

  set headlessCoordinator(bool isHeadless);

  bool get isHeadlessCoordinator;

  /// Initialize the action provider and start consuming streams
  Future<void> initialize();

  /// Start gameplay mode (coordinator sends start signal)
  Future<void> startGameplay();

  /// Resume gameplay mode (coordinator sends resume signal)
  Future<void> resumeGameplay();

  /// Stop gameplay mode (coordinator sends stop signal)
  Future<void> stopGameplay();

  /// Check if this node is the coordinator
  bool get isCoordinator;

  /// Get the current player's team assignment
  PlayerAssignment get currentPlayerAssignment;

  // Add safe getter that returns null for headless coordinator
  PlayerAssignment? get currentPlayerAssignmentOrNull;

  /// Get all player assignments
  List<PlayerAssignment> get playerAssignments;

  /// Dispose resources
  void dispose();
}

/// Local action provider - no networking, single player
class LocalActionProvider implements ActionProvider {
  final ActionStreamManager _actionManager;
  late final NetworkBridge _networkBridge;
  bool _initialized = false;

  bool _isHeadlessCoordinator = false;

  @override
  set headlessCoordinator(bool isHeadless) {
    _isHeadlessCoordinator = isHeadless;
  }

  @override
  bool get isHeadlessCoordinator => _isHeadlessCoordinator;

  @override
  ActionStreamManager get actionManager => _actionManager;

  @override
  NetworkBridge get networkBridge => _networkBridge;

  @override
  bool get isCoordinator => true; // Always coordinator in local mode

  @override
  PlayerAssignment get currentPlayerAssignment {
    if (_isHeadlessCoordinator) {
      throw StateError('Headless coordinator has no player assignment');
    }

    return PlayerAssignment(
      nodeId: 'local',
      nodeName: 'Local Player',
      teamId: 0,
      playerId: 'local_player',
      isCoordinator: true,
    );
  }

  @override
  PlayerAssignment? get currentPlayerAssignmentOrNull {
    if (_isHeadlessCoordinator) return null;
    return currentPlayerAssignment;
  }

  @override
  List<PlayerAssignment> get playerAssignments => [currentPlayerAssignment];

  LocalActionProvider(ActionStreamManager? actionManager)
    : _actionManager = actionManager ?? ActionStreamManager();

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _networkBridge = NetworkBridge(_actionManager, useLocalNetwork: true);
    await _networkBridge.initialize();
  }

  @override
  Future<void> startGameplay() async {
    // Nothing special needed for local mode
  }

  @override
  Future<void> resumeGameplay() async {
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

  bool _initialized = false;

  bool _isHeadlessCoordinator = false;

  @override
  set headlessCoordinator(bool isHeadless) {
    _isHeadlessCoordinator = isHeadless;
  }

  @override
  bool get isHeadlessCoordinator => _isHeadlessCoordinator;

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
  PlayerAssignment? get currentPlayerAssignmentOrNull {
    return _networkCoordinator.currentPlayerAssignmentOrNull;
  }

  @override
  List<PlayerAssignment> get playerAssignments {
    // Return all assignments except coordinator in headless mode
    if (!_networkCoordinator.coordinatorIsPlayer &&
        _networkCoordinator.isCoordinator) {
      return _networkCoordinator.playerAssignments
          .where((a) => !a.isCoordinator)
          .toList();
    }
    return _networkCoordinator.playerAssignments;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
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
  Future<void> resumeGameplay() async {
    // Only coordinator can start the game
    if (isCoordinator) {
      await _networkCoordinator.resumeGame();
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
