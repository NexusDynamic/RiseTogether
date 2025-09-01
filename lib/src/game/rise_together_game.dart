import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
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
import 'package:rise_together/src/attributes/team_provider.dart';
import 'package:rise_together/src/services/network_coordinator.dart'
    show PlayerAssignment, NetworkCoordinator;
import 'rise_together_world.dart';

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

class RiseTogetherGame extends Forge2DGame
    with
        KeyboardEvents,
        SingleGameInstance,
        AppLogging,
        AppSettings,
        Resetable,
        TeamProvider {
  final int nTeams = 2;
  late final RouterComponent router;
  final TimeProvider timeProvider = TimeProvider();
  final TournamentManager tournamentManager = TournamentManager();
  final DistanceTracker distanceTracker = DistanceTracker();
  final PlayerContext _playerContext = PlayerContext();

  // Action provider injected from app - abstracts networking
  ActionProvider? _actionProvider;
  bool get isConfigured => _actionProvider != null;

  final List<RiseTogetherWorld> worlds = [];
  final List<CameraComponent> cameras = [];
  final List<WorldController> worldControllers = [];
  final List<Paddle> paddles = [];

  @override
  PlayerContext? get playerContext => _playerContext;

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
    await _actionProvider!.initialize();
    await _initializeActionSystem();

    // Load game configuration from network coordinator if available
    if (actionProvider is NetworkActionProvider) {
      _loadNetworkConfiguration(actionProvider.networkCoordinator);
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
    resumeEngine();
    appLog.info('Game started');
  }

  /// Stop the game (can only be called by coordinator)
  Future<void> stopGame() async {
    if (!isConfigured) return;

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

  List<Forge2DWorld> _buildWorlds() {
    for (int i = 0; i < nTeams; i++) {
      final world = RiseTogetherWorld(level: level);
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
    for (int index = 0; index < worlds.length; index++) {
      final worldCamera =
          CameraComponent(
              world: worlds[index],
              viewport: FixedSizeViewport(viewportSize.x, viewportSize.y)
                ..position = alignedVector(
                  longMultiplier: index == 0 ? 0.0 : 1 / (index + 1),
                  shortMultiplier: 0.0,
                )
                //..size = Vector2(size.x / 2, size.y)
                ..addAll([
                  viewportRimGenerator(viewportSize),
                  if (index == 1)
                    viewportRimGenerator(viewportSize, overlay: true),
                ]),
            )
            ..viewfinder.anchor = Anchor.center
            ..viewfinder.zoom = zoomLevel;
      cameras.add(worldCamera);
      (worlds[index] as RiseTogetherWorld).setWorldCamera(worldCamera);
    }
    return cameras;
  }

  Future<void> _addPaddles() async {
    if (paddles.isNotEmpty) {
      appLog.warning('Paddles already added, skipping paddle creation');
      return;
    }
    for (int i = 0; i < cameras.length; i++) {
      final camera = cameras[i];
      final world = camera.world as RiseTogetherWorld;
      final paddle = world.buildPaddle();
      world.add(paddle);
      final ball = world.buildBall();
      world.add(ball);

      // wait for the paddle to be loaded
      await paddle.loaded;
      paddles.add(paddle);
      appLog.fine('Adding paddle to camera: ${camera.hashCode}');
      camera.follow(paddle);

      // Set starting height for distance tracking
      final ballStartHeight = ball.body.position.y;
      final actualTeamId = getActualTeamId(i);
      final team = Team.fromId(actualTeamId);
      distanceTracker.setStartingHeight(actualTeamId, ballStartHeight);
      appLog.info(
        'Display position $i (${team.shortName}) ball starting height: $ballStartHeight',
      );

      // Note: World controllers will be connected during configuration
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
      final teamStream = actionManager.createTeamStream(
        actualTeamId,
        5,
      ); // max 5 players per team
      final worldController = WorldController(
        world: worlds[displayIndex],
        actionStream: teamStream,
      );

      // Connect paddle if it exists
      if (displayIndex < paddles.length) {
        worldController.setPaddle(paddles[displayIndex]);
        appLog.fine(
          'Connected paddle at display position $displayIndex (actual team $actualTeamId) to world controller',
        );
      }

      worldControllers.add(worldController);
      worldController.initialize();
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
    super.update(dt);
    if (isGameOver) {
      return;
    }
    timeProvider.updateTime(dt);

    // Update distance tracking for each team
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

          // Debug logging (remove after testing)
          // final team = Team.fromId(actualTeamId);
          // if (distance > 0.1) {
          //   appLog.info(
          //     'Display $displayIndex (${team.shortName}) - Ball height: $ballHeight, Distance: ${distance.toStringAsFixed(1)}m',
          //   );
          // }
        }
      }
    }

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
  void _loadNetworkConfiguration(NetworkCoordinator networkCoordinator) {
    appLog.info('Loading game configuration from network coordinator');

    final config = networkCoordinator.getEffectiveGameConfiguration();
    appLog.info('Received configuration keys: ${config.keys.toList()}');

    // Load game-specific settings from network configuration
    if (config.containsKey('game')) {
      final gameConfig = config['game'] as Map<String, dynamic>;

      if (gameConfig.containsKey('level_duration')) {
        final levelDuration = (gameConfig['level_duration'] as num).toDouble();
        timeProvider.initialize(levelDuration);
        appLog.info('Set level duration from network: ${levelDuration}s');
      }

      if (gameConfig.containsKey('tournament_rounds') &&
          gameConfig.containsKey('levels_per_round')) {
        final tournamentRounds = gameConfig['tournament_rounds'] as int;
        final levelsPerRound = gameConfig['levels_per_round'] as int;
        tournamentManager.initialize(tournamentRounds, levelsPerRound);
        appLog.info(
          'Set tournament settings from network: $tournamentRounds rounds, $levelsPerRound levels per round',
        );
      }

      if (gameConfig.containsKey('distance_multiplier')) {
        final distanceMultiplier = (gameConfig['distance_multiplier'] as num)
            .toDouble();
        distanceTracker.initialize(distanceMultiplier);
        appLog.info(
          'Set distance multiplier from network: $distanceMultiplier',
        );
      }
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
