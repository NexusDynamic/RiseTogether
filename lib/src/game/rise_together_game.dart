import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame/layers.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame/events.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:logging/logging.dart' show Level;
import 'package:rise_together/src/components/paddle.dart';
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
  Map<String, int>? _teamPlayerCounts;

  final List<RiseTogetherWorld> worlds = [];
  final List<CameraComponent> cameras = [];
  final List<WorldController> worldControllers = [];
  final List<Paddle> paddles = [];

  // @override
  // PlayerContext get playerContext => _playerContext;

  ActionStreamManager get actionManager => _actionProvider!.actionManager;

  final isGameOver = false;

  final RiseTogetherLevel level;

  RiseTogetherGame({this.level = const Level1()})
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

    await _initializeActionSystem();

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

  /// Get team mapping where player's team is always on the left (index 0)
  /// Returns a map: displayIndex -> actualTeamId
  Map<int, int> get teamDisplayMapping {
    final playerAssignment = currentPlayerAssignment;
    if (playerAssignment == null) {
      // Default mapping when no assignment is available
      return {0: 0, 1: 1};
    }

    final playerTeamId = playerAssignment.teamId;
    final opponentTeamId = playerTeamId == 0 ? 1 : 0;

    // Player's team is always shown on left (display index 0)
    // Opponent's team is always shown on right (display index 1)
    return {
      0: playerTeamId, // Left display = player's actual team
      1: opponentTeamId, // Right display = opponent's actual team
    };
  }

  /// Get the actual team ID for a display position (0=left, 1=right)
  int getActualTeamId(int displayIndex) {
    return teamDisplayMapping[displayIndex] ?? displayIndex;
  }

  /// Get the display index for an actual team ID
  int getDisplayIndex(int actualTeamId) {
    final mapping = teamDisplayMapping;
    for (final entry in mapping.entries) {
      if (entry.value == actualTeamId) {
        return entry.key;
      }
    }
    return actualTeamId; // Fallback
  }

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

    for (int displayIndex = 0; displayIndex < nTeams; displayIndex++) {
      final actualTeamId = getActualTeamId(displayIndex);
      final teamStream = actionManager.getTeamStream(actualTeamId);
      final thrust = teamStream?.getCurrentThrust();

      if (thrust != null) {
        // final prevLeft = _bitflagsNotifier.getLeftBitflags(actualTeamId);
        // final prevRight = _bitflagsNotifier.getRightBitflags(actualTeamId);

        // Update bitflags in notifier (will notify if changed)
        _bitflagsNotifier.updateBitflags(
          actualTeamId,
          thrust.leftBitflags,
          thrust.rightBitflags,
        );
      }
    }
  }

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

    // Find which display index this world belongs to
    final displayIndex = worlds.indexOf(world);
    if (displayIndex == -1) {
      appLog.warning('Could not find world in worlds list for action clearing');
      return;
    }

    final actualTeamId = getActualTeamId(displayIndex);
    appLog.info(
      'Clearing actions for team $actualTeamId (displayIndex: $displayIndex)',
    );

    // Clear actions for the affected team
    if (isCoordinator && _actionProvider is NetworkActionProvider) {
      final networkProvider = _actionProvider as NetworkActionProvider;
      final playerAssignments =
          networkProvider.networkCoordinator.playerAssignments;

      // First clear the local action stream for this team
      final teamStream = actionManager.getTeamStream(actualTeamId);
      teamStream?.clearAllActions();

      // Then send "none" action to participants on this team
      for (final assignment in playerAssignments) {
        if (assignment.teamId == actualTeamId && !assignment.isCoordinator) {
          // Use nodeId (UUID) for consistency with UI actions
          sendAction(actualTeamId, assignment.nodeId, PaddleAction.none);
        }
      }
    } else if (_actionProvider is LocalActionProvider) {
      // For local mode, clear actions directly
      final teamStream = actionManager.getTeamStream(actualTeamId);
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

  List<Forge2DWorld> _buildWorlds() {
    for (int i = 0; i < nTeams; i++) {
      final world = RiseTogetherWorld(level: level, left: i == 0);
      worlds.add(world);
    }
    return worlds;
  }

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

  List<CameraComponent> _buildCameras(List<Forge2DWorld> worlds) {
    final viewportSize = alignedVector(longMultiplier: 1 / nTeams);
    final zoomLevel = viewportSize.x / level.horizontalWidth;
    for (int displayIndex = 0; displayIndex < worlds.length; displayIndex++) {
      // displayIndex 0 = left side (player's team), displayIndex 1 = right side (opponent's team)
      final isPlayerTeam =
          displayIndex == 0; // Left side is always player's team
      final cameraPos = alignedVector(
        longMultiplier: displayIndex == 0
            ? 0.0
            : 0.5, // Left = 0.0, Right = 0.5
        shortMultiplier: 0.0,
      );

      final worldCamera =
          CameraComponent(
              world: worlds[displayIndex],
              viewport: FixedSizeViewport(viewportSize.x, viewportSize.y)
                ..position = cameraPos
                //..size = Vector2(size.x / 2, size.y)
                ..addAll([
                  viewportRimGenerator(viewportSize),
                  if (!isPlayerTeam)
                    viewportRimGenerator(viewportSize, overlay: true),
                ]),
            )
            ..viewfinder.anchor = Anchor.center
            ..viewfinder.zoom = zoomLevel;
      cameras.add(worldCamera);
      (worlds[displayIndex] as RiseTogetherWorld).setWorldCamera(worldCamera);
    }
    return cameras;
  }

  Future<void> _addPaddles({bool force = false}) async {
    if (paddles.isNotEmpty && !force) {
      appLog.warning('Paddles already added, skipping paddle creation');
      return;
    } else {
      for (final paddle in paddles) {
        paddle.removeFromParent();
      }
      paddles.clear();
    }
    for (int i = 0; i < cameras.length; i++) {
      final camera = cameras[i];
      final world = camera.world as RiseTogetherWorld;
      final paddle = world.buildPaddle(
        widthMultiplier: appSettings.getDouble(
          'physics.paddle_width_multiplier',
        ),
      );
      world.add(paddle);

      // wait for the paddle to be loaded
      await paddle.loaded;
      paddles.add(paddle);
      appLog.fine('Adding paddle to camera: ${camera.hashCode}');
      camera.follow(paddle);

      if (!force) {
        final ball = world.buildBall();
        world.add(ball);
        await ball.loaded;
        // Set starting height for distance tracking
        final ballStartHeight = ball.body.position.y;
        final actualTeamId = getActualTeamId(i);
        final team = Team.fromId(actualTeamId);
        distanceTracker.setStartingHeight(actualTeamId, ballStartHeight);
        appLog.info(
          'Display position $i (${team.shortName}) ball starting height: $ballStartHeight',
        );
      }

      // Connect to existing world controllers if they exist (for paddle recreation)
      if (force && worldControllers.length > i) {
        worldControllers[i].setPaddle(paddles[i]);
        appLog.fine('Reconnected world controller $i to new paddle');
      }
    }
  }

  Future<void> _initializeActionSystem() async {
    appLog.fine('Initializing action system');

    // Clean up existing world controllers
    for (final worldController in worldControllers) {
      appLog.fine(
        'Disposing existing WorldController: ${worldController.hashCode} for team ${worldController.actionStream.teamId}',
      );
      worldController.actionStream.dispose();
      worldController.dispose();
    }
    worldControllers.clear();

    // Create team streams and world controllers using injected action manager
    // Use display-based indexing (0=left/player, 1=right/opponent)
    for (int displayIndex = 0; displayIndex < nTeams; displayIndex++) {
      final actualTeamId = getActualTeamId(displayIndex);
      final currentPlayerTeam = currentPlayerAssignment?.teamId;

      appLog.info(
        'WORLD MAPPING: displayIndex=$displayIndex -> actualTeamId=$actualTeamId (camera pos=${displayIndex == 0 ? "LEFT" : "RIGHT"}) | PlayerTeam=$currentPlayerTeam',
      );

      final teamStream = actionManager.createTeamStream(
        actualTeamId,
        5, // max 5 players per team
        getPlayerBitflags: _getPlayerBitflagsMap,
      );
      // Get configured team player count (defaults to 5 if not configured)
      final configuredPlayerCount = _teamPlayerCounts != null
          ? _teamPlayerCounts![actualTeamId.toString()] ?? 5
          : 5;

      // Set the configured team player count for proper thrust calculation
      teamStream.setConfiguredTeamPlayerCount(configuredPlayerCount);

      final worldController = WorldController(
        world: worlds[displayIndex],
        actionStream: teamStream,
        shouldUpdateParallax:
            _isAuthoritativePhysics, // Only coordinator updates parallax via WorldController
        configuredTeamPlayerCount: configuredPlayerCount,
      );

      // Connect paddle if it exists
      if (displayIndex < paddles.length) {
        worldController.setPaddle(paddles[displayIndex]);
      }

      worldControllers.add(worldController);
      worldController.initialize();
    }

    // Check if current assignments match the display mapping and swap streams if needed
    if (currentPlayerAssignment != null) {
      final playerTeam = currentPlayerAssignment!.teamId;
      final expectedPlayerDisplayTeam = getActualTeamId(
        0,
      ); // Left should be player's team

      appLog.info(
        'STREAM MAPPING CHECK: PlayerTeam=$playerTeam, LeftDisplayTeam=$expectedPlayerDisplayTeam',
      );

      // If player team is not on the left (display index 0), swap the streams
      if (playerTeam != expectedPlayerDisplayTeam &&
          worldControllers.length >= 2) {
        appLog.info(
          'SWAPPING STREAMS: Player team $playerTeam should be on left, swapping streams',
        );

        final stream0 = worldControllers[0].actionStream;
        final stream1 = worldControllers[1].actionStream;

        worldControllers[0].setActionStream(stream1);
        worldControllers[1].setActionStream(stream0);

        appLog.info(
          'STREAMS SWAPPED: Left now gets team ${stream1.teamId}, Right now gets team ${stream0.teamId}',
        );
      }
    }

    appLog.fine(
      'Action system initialized with ${worldControllers.length} world controllers',
    );
  }

  @override
  Future<void> onLoad() async {
    appLog.setMinLevel(Level.INFO);
    appLog.fine('RiseTogetherGame onLoad called');
    // Ensure game settings store is loaded
    await initSettings();
    appLog.fine('App settings initialized: $appSettings');

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

    _buildCameras(_buildWorlds());
    addAll(worlds);
    addAll(cameras);
    await _addPaddles();

    appLog.fine('Game assets loaded, ready for configuration');
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    super.onKeyEvent(event, keysPressed);
    if (!isLoaded || !isConfigured) {
      return KeyEventResult.ignored;
    }

    // Only handle keyboard input in local mode or debug mode
    if (_shouldEnableKeyboardInput()) {
      _handleKeyboardActions(keysPressed);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Check if keyboard input should be enabled
  bool _shouldEnableKeyboardInput() {
    // Always allow in local mode (no networking)
    if (_actionProvider is LocalActionProvider) {
      return true;
    }

    // Allow in debug mode
    try {
      if (appSettings.getBool('game.debug_mode')) {
        return true;
      }
    } catch (e) {
      appLog.warning('Could not access debug_mode setting: $e');
    }

    return false;
  }

  void _handleKeyboardActions(Set<LogicalKeyboardKey> keysPressed) {
    // Left side keyboard controls (player's team - display index 0)
    final leftTeamId = getActualTeamId(0);
    final leftTeam = Team.fromId(leftTeamId);
    final playerLeft = PlayerId.fromTeamAndId(leftTeam, 'keyboard_player_left');
    PaddleAction actionLeft = PaddleAction.none;

    if (keysPressed.contains(LogicalKeyboardKey.keyA)) {
      actionLeft = PaddleAction.left;
    } else if (keysPressed.contains(LogicalKeyboardKey.keyD)) {
      actionLeft = PaddleAction.right;
    }

    _actionProvider!.networkBridge.sendAction(
      leftTeamId,
      playerLeft.id,
      actionLeft,
    );

    // Right side keyboard controls (opponent's team - display index 1)
    final rightTeamId = getActualTeamId(1);
    final rightTeam = Team.fromId(rightTeamId);
    final playerRight = PlayerId.fromTeamAndId(
      rightTeam,
      'keyboard_player_right',
    );
    PaddleAction actionRight = PaddleAction.none;

    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      actionRight = PaddleAction.left;
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      actionRight = PaddleAction.right;
    }

    _actionProvider!.networkBridge.sendAction(
      rightTeamId,
      playerRight.id,
      actionRight,
    );
  }

  @override
  void update(double dt) {
    if (isGameOver) {
      return;
    }

    // Always run the full engine update for rendering and component lifecycle
    super.update(dt);
    if (!_isAuthoritativePhysics) {
      // reset ball and paddle velocities to zero
      for (final world in worlds) {
        world.ball.body.linearVelocity = Vector2.zero();
        world.ball.body.angularVelocity = 0.0;
        world.paddle.body.linearVelocity = Vector2.zero();
        world.paddle.body.angularVelocity = 0.0;
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

    // Reset any world components that implement Resetable
    for (final world in worlds) {
      if (world is Resetable) {
        (world as Resetable).reset();
      }
    }

    // Reset any world controllers that implement Resetable
    for (final controller in worldControllers) {
      if (controller is Resetable) {
        (controller as Resetable).reset();
      }
    }

    // Pause the engine until user starts again
    pauseEngine();

    appLog.info('Game state reset complete');
  }

  /// Load configuration from network coordinator (for participants)
  void _loadNetworkConfiguration(NetworkCoordinator networkCoordinator) async {
    appLog.info('Loading game configuration from network coordinator');

    final config = networkCoordinator.getEffectiveGameConfiguration();
    appLog.info('Received configuration keys: ${config.keys.toList()}');

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
      _teamPlayerCounts = Map<String, int>.from(config['teams']);
      appLog.info('Received team player counts: $_teamPlayerCounts');

      // Update existing TeamActionStreams with correct team player counts
      for (int displayIndex = 0; displayIndex < nTeams; displayIndex++) {
        final actualTeamId = getActualTeamId(displayIndex);
        final configuredPlayerCount =
            _teamPlayerCounts![actualTeamId.toString()] ?? 5;
        final teamStream = actionManager.getTeamStream(actualTeamId);
        teamStream?.setConfiguredTeamPlayerCount(configuredPlayerCount);

        // Also update WorldController if it exists
        if (displayIndex < worldControllers.length) {
          // Note: WorldController configuredTeamPlayerCount is final, can't update
          // This is why we need to recreate them or use the ActionStream approach
        }
      }
    }

    if (config.containsKey('physics')) {
      final physicsConfig = config['physics'] as Map<String, dynamic>;
      await appSettings.getGroup('physics').updateFromMap(physicsConfig);
      appLog.info('Applied physics configuration from network');
    }

    // Always recreate paddles after any configuration update to ensure all settings are applied
    await _addPaddles(force: true);
    appLog.info('Recreated paddles with updated configuration');

    if (config.containsKey('network')) {
      final networkConfig = config['network'] as Map<String, dynamic>;
      await appSettings.getGroup('network').updateFromMap(networkConfig);
      appLog.info('Applied network configuration from network');
    }

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
    _addPaddles(force: true);
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
    for (int displayIndex = 0; displayIndex < nTeams; displayIndex++) {
      if (displayIndex < worlds.length) {
        final world = worlds[displayIndex];
        final actualTeamId = getActualTeamId(displayIndex);
        if (world.ball.isMounted) {
          final ballHeight = world.ball.position.y;
          distanceTracker.updateBallPosition(actualTeamId, ballHeight);

          // Update tournament manager with current distances
          final distance = distanceTracker.getTeamDistance(actualTeamId);
          tournamentManager.updateTeamDistance(actualTeamId, distance);
        }
      }
    }
  }

  /// Set up physics state provider for coordinator
  void _setupPhysicsStateProvider(NetworkCoordinator coordinator) {
    coordinator.setPhysicsStateProvider(_getCurrentPhysicsState);
    appLog.info('Physics state provider set up for coordinator');
  }

  /// Get current physics state for broadcasting (coordinator only)
  List<double>? _getCurrentPhysicsState() {
    if (!_isAuthoritativePhysics || worlds.length < nTeams) return null;

    final state = <double>[];

    // For each team: ballX, ballY, ballRotation, paddleY, paddleAngle, stateL, stateR
    for (int displayIndex = 0; displayIndex < nTeams; displayIndex++) {
      final actualTeamId = getActualTeamId(displayIndex);
      final world = worlds[displayIndex];

      if (world.ball.isMounted && world.paddle.isMounted) {
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
        final teamStream = actionManager.getTeamStream(actualTeamId);
        final thrust = teamStream?.getCurrentThrust();
        state.add(
          (thrust?.leftBitflags ?? 0).toDouble(),
        ); // stateL (leftBitflags as float)
        state.add(
          (thrust?.rightBitflags ?? 0).toDouble(),
        ); // stateR (rightBitflags as float)
      } else {
        // Add default values if components not ready
        state.addAll([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
      }
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

    // final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // appLog.info(
    //   'Now: $now, buffer timestamps: ${_stateBuffer.map((s) => s.timestamp.toStringAsFixed(3)).join(", ")}',
    // );

    // If we have multiple states, try to interpolate between them
    // if (_stateBuffer.length >= 2) {
    //   // Find the two states to interpolate between
    //   PhysicsSnapshot? previous;
    //   PhysicsSnapshot? next;

    //   for (final state in _stateBuffer) {
    //     if (state.timestamp <= now) {
    //       previous = state;
    //     } else {
    //       next = state;
    //       break;
    //     }
    //   }

    //   if (previous != null && next != null) {
    //     // Calculate interpolation factor
    //     final alpha =
    //         (now - previous.timestamp) / (next.timestamp - previous.timestamp);
    //     final clampedAlpha = alpha.clamp(0.0, 1.0);

    //     // Apply interpolated state to each world
    //     for (
    //       int displayIndex = 0;
    //       displayIndex < nTeams && displayIndex < worlds.length;
    //       displayIndex++
    //     ) {
    //       final world = worlds[displayIndex];
    //       final stateOffset = displayIndex * 6; // 6 values per team

    //       if (stateOffset + 5 < previous.state.length &&
    //           stateOffset + 5 < next.state.length &&
    //           world.ball.isMounted &&
    //           world.paddle.isMounted) {
    //         // Interpolate ball position
    //         final ballX = _lerp(
    //           previous.state[stateOffset],
    //           next.state[stateOffset],
    //           clampedAlpha,
    //         );
    //         final ballY = _lerp(
    //           previous.state[stateOffset + 1],
    //           next.state[stateOffset + 1],
    //           clampedAlpha,
    //         );
    //         world.ball.setPosition(Vector2(ballX, ballY));
    //         appLog.info('Set ball position to ($ballX, $ballY)');
    //         // Interpolate paddle position (only Y)
    //         final paddleY = _lerp(
    //           previous.state[stateOffset + 2],
    //           next.state[stateOffset + 2],
    //           clampedAlpha,
    //         );
    //         world.paddle.setPosition(Vector2(world.paddle.position.x, paddleY));
    //         appLog.info('Set paddle Y position to $paddleY');
    //         // Interpolate paddle angle
    //         final paddleAngle = _lerp(
    //           previous.state[stateOffset + 3],
    //           next.state[stateOffset + 3],
    //           clampedAlpha,
    //         );
    //         world.paddle.setAngle(paddleAngle);
    //       }
    //     }
    //   }
    // } else {
    // If we only have one state, apply it directly
    final latestState = _stateBuffer.last;

    // Apply latest state directly to each world
    for (
      int displayIndex = 0;
      displayIndex < nTeams && displayIndex < worlds.length;
      displayIndex++
    ) {
      final world = worlds[displayIndex];
      final actualTeamId = getActualTeamId(displayIndex);
      final stateOffset =
          actualTeamId *
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
        _bitflagsNotifier.updateBitflags(
          actualTeamId,
          leftBitflags,
          rightBitflags,
        );

        // Update parallax background for participants using proportional thrust
        if (!_isAuthoritativePhysics && _teamPlayerCounts != null) {
          final leftPlayerCount = _countSetBits(leftBitflags);
          final rightPlayerCount = _countSetBits(rightBitflags);
          final teamPlayerCount =
              _teamPlayerCounts![actualTeamId.toString()] ?? 5;
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
    final displayIndex = getDisplayIndex(teamId);

    if (displayIndex < worldControllers.length) {
      final teamStream = actionManager.getTeamStream(teamId);

      if (teamStream != null && displayIndex < worlds.length) {
        // Get current thrust from local inputs
        final thrust = teamStream.getCurrentThrust();
        final world = worlds[displayIndex];

        if (world.paddle.isMounted) {
          // Apply predicted movement locally (will be corrected by authoritative state)
          final totalThrust = thrust.leftThrust + thrust.rightThrust;
          final predictedVelocity = Vector2(0, -totalThrust);

          // Apply small prediction offset (much smaller than authoritative physics)
          world.paddle.body.linearVelocity =
              predictedVelocity * 0.1; // Reduced impact for prediction

          // Note: Parallax background is now updated by authoritative physics state
          // to ensure both teams get proper starfield updates
        }
      }
    }
  }

  @override
  void onRemove() {
    // Clean up resources
    for (final controller in worldControllers) {
      controller.dispose();
    }

    // Dispose action provider if configured
    if (isConfigured) {
      _actionProvider!.dispose();
    }

    super.onRemove();
  }
}
