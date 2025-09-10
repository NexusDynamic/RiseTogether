import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame/events.dart';
import 'package:flutter/cupertino.dart';
import 'package:logging/logging.dart' show Level;
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/models/team.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/settings/app_settings.dart';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/game/world_controller.dart';
import 'package:rise_together/src/game/tournament_manager.dart';
import 'package:rise_together/src/game/distance_tracker.dart';
import 'package:rise_together/src/game/action_provider.dart';
import 'package:rise_together/src/attributes/resetable.dart';
// import 'package:rise_together/src/attributes/team_provider.dart';
import 'package:rise_together/src/services/network_coordinator.dart'
    show PlayerAssignment, NetworkCoordinator;
import 'package:rise_together/src/models/team_context.dart';
import 'rise_together_world.dart';
import 'dart:collection';

/// Notifier for player input bitflag changes
class BitflagsNotifier with ChangeNotifier {
  final Map<int, int> _leftBitflags = {}; // teamId -> leftBitflags
  final Map<int, int> _rightBitflags = {}; // teamId -> rightBitflags

  int getLeftBitflags(int teamId) => _leftBitflags[teamId] ?? 0;
  int getRightBitflags(int teamId) => _rightBitflags[teamId] ?? 0;

  void updateBitflags(int teamId, int leftBitflags, int rightBitflags) {
    final prevLeft = _leftBitflags[teamId] ?? 0;
    final prevRight = _rightBitflags[teamId] ?? 0;

    if (leftBitflags != prevLeft || rightBitflags != prevRight) {
      _leftBitflags[teamId] = leftBitflags;
      _rightBitflags[teamId] = rightBitflags;
      notifyListeners();
    }
  }

  void clear() {
    _leftBitflags.clear();
    _rightBitflags.clear();
    notifyListeners();
  }
}

/// Physics snapshot for authoritative physics state
class PhysicsSnapshot {
  final double timestamp;
  final List<double>
  state; // Team1: ballX, ballY, ballRotation, paddleY, paddleAngle, stateL, stateR + Team2: ballX, ballY, ballRotation, paddleY, paddleAngle, stateL, stateR

  PhysicsSnapshot({required this.timestamp, required this.state});
}

/// A provider for tracking game time with countdown functionality.
class TimeProvider extends ChangeNotifier with Resetable {
  double _timeRemaining = 0.0;
  double _duration = 120.0;
  bool _isComplete = false;

  double get timeRemaining => _timeRemaining;
  double get duration => _duration;
  bool get isComplete => _isComplete;

  void initialize(double duration) {
    _duration = duration;
    _timeRemaining = duration;
    _isComplete = false;
    notifyListeners();
  }

  void updateTime(double dt) {
    if (_isComplete) return;

    _timeRemaining -= dt;
    if (_timeRemaining <= 0) {
      _timeRemaining = 0;
      _isComplete = true;
    }
    notifyListeners();
  }

  @override
  void reset() {
    _timeRemaining = _duration;
    _isComplete = false;
    notifyListeners();
  }

  String get formattedTime {
    final totalSeconds = _timeRemaining.ceil();
    final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class RiseTogetherGame<T extends RiseTogetherWorld> extends Forge2DGame
    with
        KeyboardEvents,
        SingleGameInstance,
        AppLogging,
        AppSettings,
        Resetable {
  final int nTeams = 2;
  late final RouterComponent router;
  final TimeProvider timeProvider = TimeProvider();
  final TournamentManager tournamentManager = TournamentManager();
  final DistanceTracker distanceTracker = DistanceTracker();
  // final PlayerContext _playerContext = PlayerContext();

  // Action provider injected from app - abstracts networking
  ActionProvider? _actionProvider;
  bool get isConfigured => _actionProvider != null;

  // Cached player bitflags mapping to avoid recalculation
  Map<String, int>? _cachedPlayerBitflags;
  int? _cachedPlayerCount;

  // Notifier for bitflag changes (for UI reactivity)
  final BitflagsNotifier _bitflagsNotifier = BitflagsNotifier();

  // Authoritative physics support
  bool _isAuthoritativePhysics = false;
  final Queue<PhysicsSnapshot> _stateBuffer = Queue<PhysicsSnapshot>();
  static const int STATE_BUFFER_SIZE = 3; // Keep 3 frames for interpolation

  // Team player counts for thrust calculation (received from coordinator)
  final Map<String, int> _teamPlayerCounts = {};

  // final List<RiseTogetherWorld> worlds = [];
  final List<CameraComponent> cameras = [];
  final Map<TeamDisplayPosition, WorldController> worldControllers = {};
  // final List<Paddle> paddles = [];

  // @override
  // PlayerContext get playerContext => _playerContext;

  // ActionStreamManager get actionManager => _actionProvider!.actionManager;

  final ActionStreamManager actionManager;

  final isGameOver = false;

  final RiseTogetherLevel level;

  RiseTogetherGame({this.level = const Level1(), required this.actionManager})
    : super(gravity: Vector2.zero(), zoom: 10) {
    paused = true; // Start paused
  }

  /// Configure the game with an action provider
  /// This separates asset loading from networking configuration
  Future<void> configure(ActionProvider actionProvider) async {
    if (_actionProvider != null) {
      _actionProvider!.dispose();
    }
    _actionProvider = actionProvider;

    // Invalidate cached bitflags when changing providers
    _cachedPlayerBitflags = null;
    _cachedPlayerCount = null;

    // Initialize bitflag notifier
    _bitflagsNotifier.clear();

    await _actionProvider!.initialize();

    // Determine if this instance is authoritative for physics
    _isAuthoritativePhysics = actionProvider.isCoordinator;
    appLog.info(
      'Physics mode: ${_isAuthoritativePhysics ? "Authoritative" : "Follower"}',
    );
    appLog.info(
      'Game role - isCoordinator: ${actionProvider.isCoordinator}, deviceId: ${(actionProvider is NetworkActionProvider) ? actionProvider.networkCoordinator.deviceId : 'local'}',
    );

    // await _initializeActionSystem();

    // Load game configuration from network coordinator if available
    if (actionProvider is NetworkActionProvider) {
      _loadNetworkConfiguration(actionProvider.networkCoordinator);

      if (!_isAuthoritativePhysics) {
        // Set up callback to receive physics state when stream is ready
        appLog.info('Setting up physics reception for follower');
        actionProvider.networkCoordinator.setOnPhysicsDataReceivedCallback((
          data,
        ) {
          _handleIncomingPhysicsState(data);
        });
        appLog.info('Physics stream ready callback set up for follower');
      } else {
        // Set up physics state provider for coordinator
        appLog.info('Setting up physics state provider for coordinator');
        _setupPhysicsStateProvider(actionProvider.networkCoordinator);
      }
    } else {
      appLog.info('Using local configuration for local action provider');
    }

    appLog.info('Game configured with action provider');
  }

  /// Start the game (can only be called by coordinator)
  Future<void> startGame() async {
    if (!isConfigured) {
      throw StateError('Game must be configured before starting');
    }

    await _actionProvider!.startGameplay();

    // Start physics state broadcasting if this is the coordinator
    if (_isAuthoritativePhysics && _actionProvider is NetworkActionProvider) {
      final coordinator =
          (_actionProvider as NetworkActionProvider).networkCoordinator;
      await coordinator.startPhysicsStateBroadcast();
      appLog.info('Physics state broadcasting started for coordinator');
    }

    resumeEngine();
    appLog.info('Game started');
  }

  /// Stop the game (can only be called by coordinator)
  Future<void> stopGame() async {
    if (!isConfigured) return;

    // Stop physics state broadcasting if this is the coordinator
    if (_isAuthoritativePhysics && _actionProvider is NetworkActionProvider) {
      final coordinator =
          (_actionProvider as NetworkActionProvider).networkCoordinator;
      coordinator.stopPhysicsStateBroadcast();
      appLog.info('Physics state broadcasting stopped for coordinator');
    }

    await _actionProvider!.stopGameplay();
    pauseEngine();
    appLog.info('Game stopped');
  }

  /// Send action through the action provider
  void sendAction(int teamId, String playerId, PaddleAction action) {
    if (!isConfigured) {
      appLog.warning('Attempted to send action but game not configured');
      return;
    }
    _actionProvider!.networkBridge.sendAction(teamId, playerId, action);
  }

  /// Get whether this is the coordinator node
  bool get isCoordinator =>
      isConfigured ? _actionProvider!.isCoordinator : false;

  /// Get current player's team assignment
  PlayerAssignment? get currentPlayerAssignment =>
      isConfigured ? _actionProvider!.currentPlayerAssignment : null;

  /// Get all players sorted by team then alphabetically with their bitflag values
  /// Returns a list of maps with nodeId, teamId, playerId, and bitflagValue (2^index)
  List<Map<String, dynamic>> getAllPlayersBitflags() {
    if (!isConfigured || _actionProvider is! NetworkActionProvider) {
      return [];
    }

    final networkProvider = _actionProvider as NetworkActionProvider;
    final allPlayers = networkProvider.networkCoordinator.playerAssignments;

    // Sort players: first by team, then alphabetically by nodeId
    final sortedPlayers = List<PlayerAssignment>.from(allPlayers);
    sortedPlayers.sort((a, b) {
      // First sort by team
      final teamComparison = a.teamId.compareTo(b.teamId);
      if (teamComparison != 0) return teamComparison;

      // Then sort alphabetically by nodeId
      return a.nodeId.compareTo(b.nodeId);
    });

    // Create bitflag mapping
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < sortedPlayers.length; i++) {
      final player = sortedPlayers[i];
      result.add({
        'nodeId': player.nodeId,
        'teamId': player.teamId,
        'playerId': player.playerId,
        'bitflagValue': 1 << i, // 2^i
        'index': i,
      });
    }

    return result;
  }

  /// Get bitflag value for current device/player
  int? getCurrentPlayerBitflag() {
    final allPlayers = getAllPlayersBitflags();
    final currentAssignment = currentPlayerAssignment;

    if (currentAssignment == null) return null;

    for (final player in allPlayers) {
      if (player['nodeId'] == currentAssignment.nodeId) {
        return player['bitflagValue'] as int;
      }
    }

    return null;
  }

  /// Update current bitflags from local team streams (for coordinator)
  void _updateCurrentBitflags() {
    if (!_isAuthoritativePhysics) return;

    for (final worldController in worldControllers.values) {
      final teamId = worldController.teamContext.teamId;

      final teamStream = actionManager.getTeamStream(teamId);
      final thrust = teamStream?.getCurrentThrust();

      if (thrust != null) {
        // Update bitflags in notifier (will notify if changed)
        _bitflagsNotifier.updateBitflags(
          teamId,
          thrust.leftBitflags,
          thrust.rightBitflags,
        );
      }
    }
  }

  /// Update team contexts for all world controllers when assignments change
  /// this needs to change to only update things that need changing when
  /// the team changes.
  /// TODO: This is pretty disgusting. FIX!
  void _updateTeamContexts() {
    final myTeamId = _actionProvider!.currentPlayerAssignment.teamId;
    final myTeam = Team.fromId(myTeamId);
    final opponentTeam = myTeam.opponent;
    final myTeamPlayers = _actionProvider!.playerAssignments
        .where((p) => p.teamId == myTeamId)
        .toList();
    final opponentTeamPlayers = _actionProvider!.playerAssignments
        .where((p) => p.teamId != myTeamId)
        .toList();

    final myTeamStream = actionManager.getTeamStream(myTeamId)!;
    final opponentTeamStream = actionManager.getTeamStream(opponentTeam.id)!;

    final TeamContext myTeamContext;
    final TeamContext opponentTeamContext;
    final leftWorldController = worldControllers[TeamDisplayPosition.left];
    final rightWorldController = worldControllers[TeamDisplayPosition.right];
    if (myTeamStream.position != TeamDisplayPosition.left) {
      // need to swap.
      myTeamStream.position = TeamDisplayPosition.left;
      opponentTeamStream.position = TeamDisplayPosition.right;
      myTeamContext = rightWorldController!.teamContext;
      opponentTeamContext = leftWorldController!.teamContext;
    } else {
      myTeamContext = leftWorldController!.teamContext;
      opponentTeamContext = rightWorldController!.teamContext;
    }

    myTeamContext.isPlayerTeam = true;
    myTeamContext.displayPosition = TeamDisplayPosition.left;
    myTeamContext.assign(myTeamPlayers);

    opponentTeamContext.isPlayerTeam = false;
    opponentTeamContext.displayPosition = TeamDisplayPosition.right;
    opponentTeamContext.assign(opponentTeamPlayers);

    appLog.info(
      'Updated team contexts: Left=${myTeamContext.teamId} (${myTeamContext.players.length} players), Right=${opponentTeamContext.teamId} (${opponentTeamContext.players.length} players)',
    );

    leftWorldController.setTeamContext(myTeamContext);
    rightWorldController.setTeamContext(opponentTeamContext);
    // for (final worldController in worldControllers) {
    //   // Update team context (for colors, display text, etc.)
    //   // worldController.setTeamContext(teamContext);

    //   // Re-route ActionStream: get the stream for this team's actual ID
    //   final teamId = worldController.teamContext.teamId;
    //   final teamStream = actionManager.getTeamStream(teamId);
    //   if (teamStream != null) {
    //     // Update player count configuration
    //     final configuredPlayerCount = _teamPlayerCounts[teamId.toString()] ?? 5;

    //     teamStream.setConfiguredTeamPlayerCount(configuredPlayerCount);

    //     // Re-route the ActionStream to this WorldController
    //     worldController.setActionStream(teamStream);

    //     appLog.info(
    //       'Re-routed ActionStream[team $teamId] -> WorldController[displayIndex ${teamStream.position}] with $configuredPlayerCount players',
    //     );
    //   } else {
    //     appLog.warning('No ActionStream found for team $teamId');
    //   }
    // }

    //   appLog.info(
    //     'Updated team context for displayIndex $displayIndex: $teamContext',
    //   );
    // }

    // appLog.info('Team contexts updated for ${teamContexts.length} worlds');
  }

  /// Build team contexts for current player assignment
  /// Returns [playerTeamContext, opponentTeamContext] (left, right)
  // List<TeamContext> _buildTeamContexts() {
  //   final playerAssignment = currentPlayerAssignment;

  //   if (playerAssignment == null || _actionProvider is! NetworkActionProvider) {
  //     // Fallback for local mode or when no assignment
  //     return [
  //       TeamContext.playerTeam(absoluteTeamId: 0, players: []),
  //       TeamContext.opponentTeam(absoluteTeamId: 1, players: []),
  //     ];
  //   }

  //   final networkProvider = _actionProvider as NetworkActionProvider;
  //   final allPlayers = networkProvider.networkCoordinator.playerAssignments;

  //   final playerTeamId = playerAssignment.teamId;
  //   final opponentTeamId = playerTeamId == 0 ? 1 : 0;

  //   // Split players by team
  //   final playerTeamPlayers = allPlayers
  //       .where((p) => p.teamId == playerTeamId)
  //       .toList();
  //   final opponentTeamPlayers = allPlayers
  //       .where((p) => p.teamId == opponentTeamId)
  //       .toList();

  //   return [
  //     // Left display = player team (always)
  //     TeamContext.playerTeam(
  //       absoluteTeamId: playerTeamId,
  //       players: playerTeamPlayers,
  //     ),
  //     // Right display = opponent team (always)
  //     TeamContext.opponentTeam(
  //       absoluteTeamId: opponentTeamId,
  //       players: opponentTeamPlayers,
  //     ),
  //   ];
  // }

  /// Get player bitflags mapping by playerId (for action system)
  Map<String, int> _getPlayerBitflagsMap() {
    if (!isConfigured || _actionProvider is! NetworkActionProvider) {
      return {};
    }

    final networkProvider = _actionProvider as NetworkActionProvider;
    final playerCount =
        networkProvider.networkCoordinator.playerAssignments.length;

    // Check cache validity
    if (_cachedPlayerBitflags != null && _cachedPlayerCount == playerCount) {
      return _cachedPlayerBitflags!;
    }

    // Recalculate and cache
    final allPlayers = getAllPlayersBitflags();
    final result = <String, int>{};

    for (final player in allPlayers) {
      final playerId = player['playerId'] as String;
      final nodeId = player['nodeId'] as String;
      final bitflagValue = player['bitflagValue'] as int;

      // Standardize on nodeId (UUID) as the authoritative player identifier
      // Map both the nodeId and its remote_player hash version
      result[nodeId] = bitflagValue;
      result['remote_player_${nodeId.hashCode.abs()}'] = bitflagValue;

      // Legacy support: also map playerId in case it's used somewhere
      if (playerId != nodeId) {
        result[playerId] = bitflagValue;
      }

      // Debug logging
      appLog.info(
        'Player bitflag mapping: nodeId=$nodeId, playerId=$playerId, bitflag=$bitflagValue',
      );
    }

    _cachedPlayerBitflags = result;
    _cachedPlayerCount = playerCount;
    return result;
  }

  /// Get current left input bitflags for a team (for visual indicators)
  int getTeamLeftBitflags(int teamId) =>
      _bitflagsNotifier.getLeftBitflags(teamId);

  /// Get current right input bitflags for a team (for visual indicators)
  int getTeamRightBitflags(int teamId) =>
      _bitflagsNotifier.getRightBitflags(teamId);

  /// Clear all player actions for a specific team (when ball hits wall)
  void clearTeamActions(RiseTogetherWorld world) {
    if (!isConfigured) return;

    final worldController = world.controller;
    final teamId = worldController.teamContext.teamId;

    appLog.info('Clearing actions for team $teamId');

    // Clear actions for the affected team
    if (isCoordinator && _actionProvider is NetworkActionProvider) {
      final networkProvider = _actionProvider as NetworkActionProvider;
      final playerAssignments =
          networkProvider.networkCoordinator.playerAssignments;

      // First clear the local action stream for this team
      final teamStream = actionManager.getTeamStream(teamId);
      teamStream?.clearAllActions();

      // Then send "none" action to participants on this team
      for (final assignment in playerAssignments) {
        if (assignment.teamId == teamId && !assignment.isCoordinator) {
          // Use nodeId (UUID) for consistency with UI actions
          sendAction(teamId, assignment.nodeId, PaddleAction.none);
        }
      }
    } else if (_actionProvider is LocalActionProvider) {
      // For local mode, clear actions directly
      final teamStream = actionManager.getTeamStream(teamId);
      teamStream?.clearAllActions();
    }
  }

  /// Get notifier for bitflag changes (for UI reactivity)
  BitflagsNotifier get bitflagsNotifier => _bitflagsNotifier;

  /// Get a distinct color for a player based on their index
  Color getPlayerColor(int playerIndex) {
    final colors = [
      CupertinoColors.systemGreen,
      CupertinoColors.systemBlue,
      CupertinoColors.systemRed,
      CupertinoColors.systemOrange,
      CupertinoColors.systemPurple,
      CupertinoColors.systemYellow,
      CupertinoColors.systemTeal,
      CupertinoColors.systemPink,
    ];
    return colors[playerIndex % colors.length];
  }

  // List<Forge2DWorld> _buildWorlds() {
  //   for (int i = 0; i < nTeams; i++) {
  //     final world = RiseTogetherWorld(level: level, left: i == 0);
  //     worlds.add(world);
  //   }
  //   return worlds;
  // }

  RectangleComponent viewportRimGenerator(
    Vector2 viewportSize, {
    bool overlay = false,
  }) => RectangleComponent(size: viewportSize, anchor: Anchor.topLeft)
    ..paint.color = overlay
        ? Color.fromARGB(255, 0, 0, 0)
        : Color.fromARGB(255, 0, 200, 255)
    ..paint.strokeWidth = 2.0
    ..paint.style = overlay ? PaintingStyle.fill : PaintingStyle.stroke
    ..paint.blendMode = overlay ? BlendMode.color : BlendMode.srcOver;

  Vector2 alignedVector({
    required double longMultiplier,
    double shortMultiplier = 1.0,
  }) {
    return Vector2(
      canvasSize.x * longMultiplier,
      canvasSize.y * shortMultiplier,
    );
  }

  CameraComponent _buildCamera(
    RiseTogetherWorld world,
    TeamDisplayPosition pos,
  ) {
    final viewportSize = alignedVector(longMultiplier: 1 / 2);
    final zoomLevel = viewportSize.x / level.horizontalWidth;
    final cameraPos = alignedVector(
      longMultiplier: pos == TeamDisplayPosition.left
          ? 0.0
          : 0.5, // Left = 0.0, Right = 0.5
      shortMultiplier: 0.0,
    );

    final worldCamera =
        CameraComponent(
            world: world,
            viewport: FixedSizeViewport(viewportSize.x, viewportSize.y)
              ..position = cameraPos
              //..size = Vector2(size.x / 2, size.y)
              ..addAll([
                if (pos == TeamDisplayPosition.right)
                  viewportRimGenerator(viewportSize, overlay: true),
              ]),
          )
          ..viewfinder.anchor = Anchor.center
          ..viewfinder.zoom = zoomLevel;
    // cameras.add(worldCamera);
    // worlds[displayIndex].setWorldCamera(worldCamera);
    world.setWorldCamera(worldCamera);
    return worldCamera;
  }

  Future<void> _buildComponents(WorldController worldController) async {
    final widthMultiplier = appSettings.getDouble(
      'physics.paddle_width_multiplier',
    );
    await worldController.world.buildPaddle(widthMultiplier: widthMultiplier);
    final ball = await worldController.world.buildBall();
    final ballStartHeight = ball.body.position.y;
    distanceTracker.setStartingHeight(
      worldController.teamContext.teamId,
      ballStartHeight,
    );
  }

  // Future<void> _initializeActionSystem() async {
  //   appLog.fine('Initializing action system');

  //   // Clean up existing world controllers
  //   for (final worldController in worldControllers) {
  //     appLog.fine(
  //       'Disposing existing WorldController: ${worldController.hashCode} for team ${worldController.actionStream.teamId}',
  //     );
  //     worldController.actionStream.dispose();
  //     worldController.dispose();
  //   }
  //   worldControllers.clear();

  //   // Create ActionStreams for both teams (by actual team ID)
  //   final Map<int, TeamActionStream> actionStreams = {};
  //   for (int teamId = 0; teamId < nTeams; teamId++) {
  //     final configuredPlayerCount = _teamPlayerCounts != null
  //         ? _teamPlayerCounts![teamId.toString()] ?? 5
  //         : 5;

  //     final teamStream = actionManager.createTeamStream(
  //       teamId,
  //       5, // max 5 players per team
  //       getPlayerBitflags: _getPlayerBitflagsMap,
  //     );
  //     teamStream.setConfiguredTeamPlayerCount(configuredPlayerCount);
  //     actionStreams[teamId] = teamStream;
  //     appLog.fine(
  //       'Created ActionStream for team $teamId with $configuredPlayerCount players',
  //     );
  //   }

  //   // Create team contexts and WorldControllers for fixed display positions
  //   final teamContexts = _buildTeamContexts();

  //   for (int displayIndex = 0; displayIndex < nTeams; displayIndex++) {
  //     final teamContext = teamContexts[displayIndex];
  //     final teamId = teamContext.absoluteTeamId;

  //     // Get the ActionStream for this team's actual ID
  //     final teamStream = actionStreams[teamId]!;
  //     final configuredPlayerCount = _teamPlayerCounts != null
  //         ? _teamPlayerCounts![teamId.toString()] ?? 5
  //         : 5;

  //     appLog.info(
  //       'ROUTING: displayIndex=$displayIndex (${displayIndex == 0 ? 'LEFT' : 'RIGHT'}) <- ActionStream[team $teamId] | ${teamContext.toString()}',
  //     );

  //     final worldController = WorldController(
  //       world: worlds[displayIndex],
  //       actionStream: teamStream,
  //       shouldUpdateParallax:
  //           _isAuthoritativePhysics, // Only coordinator updates parallax via WorldController
  //       configuredTeamPlayerCount: configuredPlayerCount,
  //       teamContext: teamContext,
  //     );

  //     // Connect paddle if it exists
  //     if (displayIndex < paddles.length) {
  //       worldController.setPaddle(paddles[displayIndex]);
  //     }

  //     worldControllers.add(worldController);
  //     worldController.initialize();
  //   }

  //   // No need for stream swapping - TeamContext ensures correct mapping from start

  //   appLog.fine(
  //     'Action system initialized with ${worldControllers.length} world controllers',
  //   );
  // }

  @override
  Future<void> onLoad() async {
    appLog.setMinLevel(Level.ALL);
    appLog.fine('RiseTogetherGame onLoad called');
    // Ensure game settings store is loaded
    await initSettings();
    appLog.fine('App settings initialized: $appSettings');

    // set initial physics state

    // Note: Game-specific configuration will be loaded during configure()
    // Initialize with default values for now
    final levelDuration = appSettings.getDouble('game.level_duration');
    timeProvider.initialize(levelDuration);

    final tournamentRounds = appSettings.getInt('game.tournament_rounds');
    final levelsPerRound = appSettings.getInt('game.levels_per_round');
    tournamentManager.initialize(tournamentRounds, levelsPerRound);

    final distanceMultiplier = appSettings.getDouble(
      'game.distance_multiplier',
    );
    distanceTracker.initialize(distanceMultiplier);

    camera.removeFromParent();
    world.removeFromParent();
    children.register<CameraComponent>();
    await Flame.images.load('ball.png');

    _setupWorld(TeamDisplayPosition.left);
    _setupWorld(TeamDisplayPosition.right);

    appLog.fine('Game assets loaded, ready for configuration');
  }

  Future<void> _setupWorld(TeamDisplayPosition pos) async {
    final worldController = await _buildWorldController(pos);
    worldControllers[pos] = worldController;
    // first we need the camera
    final camera = _buildCamera(worldController.world, pos);
    // and to wait for it to be added
    await add(camera);
    cameras.add(camera);
    await add(worldController.world);
    // The components rely on the world and camera (for following the paddle).
    await _buildComponents(worldController);
  }

  Future<WorldController> _buildWorldController(TeamDisplayPosition pos) async {
    final world = RiseTogetherWorld(level: Level1(), pos: pos);

    final teamStream = actionManager.createTeamStream(
      pos,
      5, // max 5 players per team
      getPlayerBitflags: _getPlayerBitflagsMap,
    );

    final teamContext = TeamContext.byPosition(pos, actionStream: teamStream);
    final worldController = WorldController(
      world: world,
      shouldUpdateParallax:
          _isAuthoritativePhysics, // Only coordinator updates parallax via WorldController
      configuredTeamPlayerCount: 0,
      teamContext: teamContext,
    );

    // worldController.initialize();
    return worldController;
  }

  @override
  void update(double dt) {
    if (!isLoaded || isGameOver) {
      return;
    }

    // Always run the full engine update for rendering and component lifecycle
    super.update(dt);
    if (!_isAuthoritativePhysics) {
      // reset ball and paddle velocities to zero
      for (final worldController in worldControllers.values) {
        worldController.stopMovement();
      }
      // Non-coordinator: override physics with authoritative state from coordinator
      _interpolatePhysicsState(dt);

      // Still process local input for prediction
      _processLocalInputPrediction(dt);
    } else {
      // Coordinator: update current bitflags for visual indicators
      _updateCurrentBitflags();

      // Broadcast physics state changes to other participants
      if (_actionProvider is NetworkActionProvider) {
        final networkProvider = _actionProvider as NetworkActionProvider;
        networkProvider.networkCoordinator.broadcastPhysicsStateOnChange();
      }
    }

    timeProvider.updateTime(dt);

    // Update distance tracking for each team
    _updateDistanceTracking();

    // Check if level is complete
    if (timeProvider.isComplete && !isGameOver) {
      _handleLevelComplete();
    }
  }

  void _handleLevelComplete() {
    appLog.info('Level completed - time is up!');

    // Complete the level in tournament manager
    tournamentManager.completeLevel();

    // Stop game via action provider (coordinator will handle coordination)
    if (isConfigured) {
      // Fire and forget - level complete should be synchronous but start the async stop
      _actionProvider!.stopGameplay();
    }

    // Remove in-game UI
    overlays.remove('inGameUI');

    // Check if surveys are enabled
    final enableSurveys = appSettings.getBool('game.enable_surveys');

    if (enableSurveys && !tournamentManager.isTournamentComplete) {
      // Show survey first, then transition
      overlays.add('Survey');
    } else {
      // Go directly to level transition
      overlays.add('LevelTransition');
    }

    // Pause the engine
    pauseEngine();
  }

  @override
  void reset() {
    appLog.info('Resetting game state');

    // Reload settings and reinitialize components with new values
    // Fire and forget - reset should be synchronous
    _reloadSettings();

    // Reset timer (will now use updated duration)
    timeProvider.reset();

    // Reset tournament and distance tracking (will now use updated values)
    tournamentManager.reset();
    distanceTracker.reset();

    // Reset any world controllers that implement Resetable
    for (final controller in worldControllers.values) {
      (controller as Resetable).reset();
    }

    // Pause the engine until user starts again
    pauseEngine();

    appLog.info('Game state reset complete');
  }

  /// Load configuration from network coordinator (for participants)
  void _loadNetworkConfiguration(NetworkCoordinator networkCoordinator) async {
    appLog.info('Loading game configuration from network coordinator');

    final config = networkCoordinator.getEffectiveGameConfiguration();
    appLog.info('Cached configuration keys: ${config.keys.toList()}');

    // Apply configuration groups using the new updateFromMap API
    if (config.containsKey('game')) {
      final gameConfig = config['game'] as Map<String, dynamic>;
      await appSettings.getGroup('game').updateFromMap(gameConfig);
      appLog.info('Applied game configuration from network');

      // Re-initialize components with new settings
      final levelDuration = appSettings.getDouble('game.level_duration');
      timeProvider.initialize(levelDuration);

      final tournamentRounds = appSettings.getInt('game.tournament_rounds');
      final levelsPerRound = appSettings.getInt('game.levels_per_round');
      tournamentManager.initialize(tournamentRounds, levelsPerRound);

      final distanceMultiplier = appSettings.getDouble(
        'game.distance_multiplier',
      );
      distanceTracker.initialize(distanceMultiplier);

      appLog.info('Reinitialized game components with network configuration');
    }

    if (config.containsKey('colors')) {
      final colorsConfig = config['colors'] as Map<String, dynamic>;
      await appSettings.getGroup('colors').updateFromMap(colorsConfig);
      appLog.info('Applied colors configuration from network');
    }

    // Store team player counts for thrust calculation
    if (config.containsKey('teams')) {
      _teamPlayerCounts.clear();
      _teamPlayerCounts.addAll(Map<String, int>.from(config['teams']));
      // Update team contexts to apply new player counts
      appLog.info('Received team player counts: $_teamPlayerCounts');
    }

    if (config.containsKey('physics')) {
      final physicsConfig = config['physics'] as Map<String, dynamic>;
      appLog.info(
        '⚡ BEFORE UPDATE: paddle_width_multiplier = ${appSettings.getDouble('physics.paddle_width_multiplier')}',
      );
      appLog.info('⚡ UPDATING physics with: $physicsConfig');
      await appSettings.getGroup('physics').updateFromMap(physicsConfig);
      appLog.info(
        '⚡ AFTER UPDATE: paddle_width_multiplier = ${appSettings.getDouble('physics.paddle_width_multiplier')}',
      );
      appLog.info('Applied physics configuration from network');
    }

    // Always recreate paddles after any configuration update to ensure all settings are applied

    if (config.containsKey('network')) {
      final networkConfig = config['network'] as Map<String, dynamic>;
      await appSettings.getGroup('network').updateFromMap(networkConfig);
      appLog.info('Applied network configuration from network');
    }

    // Update team contexts after all configuration is loaded to ensure correct team assignments
    _updateTeamContexts();

    // await _addPaddles(force: true);
    appLog.info('Recreated paddles with updated configuration');

    appLog.info('Network configuration loaded successfully');
  }

  /// Reload settings from storage and update components
  Future<void> _reloadSettings() async {
    appLog.info('Reloading settings from storage');

    // Reload timer settings
    final levelDuration = appSettings.getDouble('game.level_duration');
    timeProvider.initialize(levelDuration);

    // Reload tournament settings
    final tournamentRounds = appSettings.getInt('game.tournament_rounds');
    final levelsPerRound = appSettings.getInt('game.levels_per_round');
    tournamentManager.initialize(tournamentRounds, levelsPerRound);

    // Reload distance tracking settings
    final distanceMultiplier = appSettings.getDouble(
      'game.distance_multiplier',
    );
    distanceTracker.initialize(distanceMultiplier);

    // Reload physics settings for each world
    // await _addPaddles(force: true);
    appLog.info('Settings reloaded successfully');
  }

  /// Public method to reset and restart the game
  void resetGame() {
    reset();
  }

  /// Public method to reload settings without full reset
  Future<void> reloadSettings() async {
    await _reloadSettings();
  }

  /// Update distance tracking for all teams
  void _updateDistanceTracking() {
    for (final worldController in worldControllers.values) {
      final teamId = worldController.teamContext.teamId;
      final world = worldController.world;

      final ballHeight = world.ball.position.y;
      distanceTracker.updateBallPosition(teamId, ballHeight);

      // Update tournament manager with current distances
      final distance = distanceTracker.getTeamDistance(teamId);
      tournamentManager.updateTeamDistance(teamId, distance);
    }
  }

  /// Set up physics state provider for coordinator
  void _setupPhysicsStateProvider(NetworkCoordinator coordinator) {
    coordinator.setPhysicsStateProvider(_getCurrentPhysicsState);
    appLog.info('Physics state provider set up for coordinator');
  }

  /// Get current physics state for broadcasting (coordinator only)
  List<double>? _getCurrentPhysicsState() {
    if (!_isAuthoritativePhysics || !isLoaded) return null;

    final state = <double>[];

    // For each team: ballX, ballY, ballRotation, paddleY, paddleAngle, stateL, stateR
    for (final worldController in worldControllers.values) {
      final teamId = worldController.teamContext.teamId;
      final world = worldController.world;

      // Ball position
      state.add(world.ball.position.x);
      state.add(world.ball.position.y);

      // Ball rotation
      state.add(world.ball.body.angle);

      // Paddle position (only Y, X doesn't change)
      state.add(world.paddle.position.y);

      // Paddle angle
      state.add(world.paddle.body.angle);

      // Player input bitflags (converted to float)
      final teamStream = actionManager.getTeamStream(teamId);
      final thrust = teamStream?.getCurrentThrust();
      state.add(
        (thrust?.leftBitflags ?? 0).toDouble(),
      ); // stateL (leftBitflags as float)
      state.add(
        (thrust?.rightBitflags ?? 0).toDouble(),
      ); // stateR (rightBitflags as float)
    }

    return state;
  }

  /// Handle incoming physics state updates
  void _handleIncomingPhysicsState(List<double> stateData) {
    if (stateData.length != 14) {
      appLog.warning('Invalid physics state data length: ${stateData.length}');
      return;
    }
    final dtNow = DateTime.now();
    final now = dtNow.millisecondsSinceEpoch / 1000.0;
    final snapshot = PhysicsSnapshot(timestamp: now, state: stateData);

    _stateBuffer.add(snapshot);
    appLog.logData(
      'app_data',
      'PHYSICS_STATE_RECEIVED',
      data: {'state': stateData},
      timestamp: dtNow,
    );

    // Keep buffer size manageable
    while (_stateBuffer.length > STATE_BUFFER_SIZE) {
      _stateBuffer.removeFirst();
    }
  }

  /// Interpolate physics state for smooth visuals on followers
  void _interpolatePhysicsState(double dt) {
    if (_stateBuffer.isEmpty) {
      appLog.warning(
        'No physics state data in buffer - participant not receiving updates',
      );
      return; // Need at least 1 state
    }

    final latestState = _stateBuffer.last;

    // Apply latest state directly to each world
    for (final worldController in worldControllers.values) {
      final world = worldController.world;

      final teamId = worldController.teamContext.teamId;

      final displayIndex = worldController.teamContext.displayPosition.index;

      final stateOffset =
          displayIndex *
          7; // 7 values per team (ballX, ballY, ballRotation, paddleY, paddleAngle, stateL, stateR)
      if (stateOffset + 6 < latestState.state.length &&
          world.ball.isMounted &&
          world.paddle.isMounted) {
        // Apply ball position directly
        final ballX = latestState.state[stateOffset];
        final ballY = latestState.state[stateOffset + 1];
        world.ball.setPosition(Vector2(ballX, ballY));
        //appLog.info('Set ball [NI] position to ($ballX, $ballY)');

        // Apply ball rotation directly
        final ballRotation = latestState.state[stateOffset + 2];
        world.ball.body.setTransform(world.ball.body.position, ballRotation);

        // Apply paddle position (only Y) directly
        final paddleY = latestState.state[stateOffset + 3];
        world.paddle.setPosition(Vector2(world.paddle.position.x, paddleY));
        //appLog.info('Set paddle [NI] Y position to $paddleY');

        // Apply paddle angle directly
        final paddleAngle = latestState.state[stateOffset + 4];
        world.paddle.setAngle(paddleAngle);

        // Extract and store input bitflags for visual indicators
        final leftBitflags = latestState.state[stateOffset + 5]
            .toInt(); // stateL
        final rightBitflags = latestState.state[stateOffset + 6]
            .toInt(); // stateR
        _bitflagsNotifier.updateBitflags(teamId, leftBitflags, rightBitflags);

        // Update parallax background for participants using proportional thrust
        if (!_isAuthoritativePhysics) {
          final leftPlayerCount = _countSetBits(leftBitflags);
          final rightPlayerCount = _countSetBits(rightBitflags);
          final teamPlayerCount = _teamPlayerCounts[teamId.toString()] ?? 5;
          final thrustPerPlayer = 1.0 / teamPlayerCount;

          // Calculate proportional thrust: same as coordinator logic
          final leftThrust = leftPlayerCount * thrustPerPlayer;
          final rightThrust = rightPlayerCount * thrustPerPlayer;
          final totalThrust = leftThrust + rightThrust;

          // Update parallax background for participants
          world.parallax.parallax!.baseVelocity.setFrom(
            Vector2(0, -totalThrust),
          );
        }
      }
    }
    //}
  }

  /// Linear interpolation helper
  // double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Count the number of set bits in an integer (for calculating player count from bitflags)
  int _countSetBits(int value) {
    int count = 0;
    while (value != 0) {
      count += value & 1;
      value >>= 1;
    }
    return count;
  }

  /// Process local input prediction for responsiveness on followers
  void _processLocalInputPrediction(double dt) {
    if (_isAuthoritativePhysics) return; // Only for followers

    final currentAssignment = currentPlayerAssignment;
    if (currentAssignment == null) return;

    final teamId = currentAssignment.teamId;

    final teamStream = actionManager.getTeamStream(teamId);

    if (teamStream != null) {
      // Get current thrust from local inputs
      final thrust = teamStream.getCurrentThrust();
      final world = worldControllers[teamStream.position]!.world;

      final totalThrust = thrust.leftThrust + thrust.rightThrust;
      final predictedVelocity = Vector2(0, -totalThrust);

      // Apply small prediction offset (much smaller than authoritative physics)
      world.paddle.body.linearVelocity =
          predictedVelocity * 0.1; // Reduced impact for prediction
    }
  }

  @override
  void onRemove() {
    // Clean up resources
    for (final controller in worldControllers.values) {
      controller.dispose();
    }

    // Dispose action provider if configured
    if (isConfigured) {
      _actionProvider!.dispose();
    }

    super.onRemove();
  }
}
