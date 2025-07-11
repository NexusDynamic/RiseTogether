import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame/events.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:logging/logging.dart' show Level;
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/models/team.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/net/network_bridge.dart';
import 'package:rise_together/src/settings/app_settings.dart';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/game/world_controller.dart';
import 'package:rise_together/src/game/tournament_manager.dart';
import 'package:rise_together/src/game/distance_tracker.dart';
import 'package:rise_together/src/attributes/resetable.dart';
import 'package:rise_together/src/attributes/team_provider.dart';
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

  final List<RiseTogetherWorld> worlds = [];
  final List<CameraComponent> cameras = [];
  final List<WorldController> worldControllers = [];

  @override
  PlayerContext? get playerContext => _playerContext;

  late final ActionStreamManager actionManager;
  late final NetworkBridge networkBridge;

  final isGameOver = false;

  final RiseTogetherLevel level;
  final bool useLocalNetwork;

  RiseTogetherGame({this.level = const Level1(), this.useLocalNetwork = true})
    : super(gravity: Vector2.zero(), zoom: 10) {
    paused = true; // Start paused
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
    for (int i = 0; i < cameras.length; i++) {
      final camera = cameras[i];
      final world = camera.world as RiseTogetherWorld;
      final paddle = world.buildPaddle();
      world.add(paddle);
      final ball = world.buildBall();
      world.add(ball);

      // wait for the paddle to be loaded
      await paddle.loaded;
      appLog.fine('Adding paddle to camera: ${camera.hashCode}');
      camera.follow(paddle);

      // Set starting height for distance tracking
      final ballStartHeight = ball.body.position.y;
      final team = Team.fromId(i);
      distanceTracker.setStartingHeight(team.id, ballStartHeight);
      appLog.info('${team.shortName} ball starting height: $ballStartHeight');

      // Connect paddle to world controller
      worldControllers[i].setPaddle(paddle);
    }
  }

  Future<void> _initializeActionSystem() async {
    appLog.fine('Initializing action system');

    // Create action stream manager
    actionManager = ActionStreamManager();

    // Create team streams and world controllers
    for (int teamId = 0; teamId < nTeams; teamId++) {
      final teamStream = actionManager.createTeamStream(
        teamId,
        5,
      ); // max 5 players per team
      final worldController = WorldController(
        world: worlds[teamId],
        actionStream: teamStream,
      );
      worldControllers.add(worldController);
      worldController.initialize();
    }

    // Initialize network bridge based on configuration
    networkBridge = NetworkBridge(
      actionManager,
      useLocalNetwork: useLocalNetwork,
    );
    await networkBridge.initialize();

    appLog.fine('Action system initialized');
  }

  @override
  Future<void> onLoad() async {
    appLog.setMinLevel(Level.FINE);
    appLog.fine('RiseTogetherGame onLoad called');
    await initSettings();
    appLog.fine('App settings initialized: $appSettings');

    // Initialize timer with level duration from settings
    final levelDuration = appSettings.getDouble('game.level_duration');
    timeProvider.initialize(levelDuration);

    // Initialize tournament settings
    final tournamentRounds = appSettings.getInt('game.tournament_rounds');
    final levelsPerRound = appSettings.getInt('game.levels_per_round');
    tournamentManager.initialize(tournamentRounds, levelsPerRound);

    // Initialize distance tracking
    final distanceMultiplier = appSettings.getDouble(
      'game.distance_multiplier',
    );
    distanceTracker.initialize(distanceMultiplier);

    camera.removeFromParent();
    world.removeFromParent();
    children.register<CameraComponent>();
    await Flame.images.load('ball.png');

    _buildCameras(_buildWorlds());

    // Initialize action system before adding paddles
    await _initializeActionSystem();

    addAll(worlds);
    addAll(cameras);
    await _addPaddles();

    appLog.fine('Game loaded, ready for MainMenu');
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    super.onKeyEvent(event, keysPressed);
    if (!isLoaded) {
      return KeyEventResult.ignored;
    }

    // Handle keyboard input through new action system
    _handleKeyboardActions(keysPressed);

    return KeyEventResult.handled;
  }

  void _handleKeyboardActions(Set<LogicalKeyboardKey> keysPressed) {
    // Team A keyboard controls (left side)
    final teamA = Team.a;
    final playerA = PlayerId.fromTeamAndId(teamA, 'keyboard_player_a');
    PaddleAction actionA = PaddleAction.none;

    if (keysPressed.contains(LogicalKeyboardKey.keyA)) {
      actionA = PaddleAction.left;
    } else if (keysPressed.contains(LogicalKeyboardKey.keyD)) {
      actionA = PaddleAction.right;
    }

    networkBridge.sendAction(teamA.id, playerA.id, actionA);

    // Team B keyboard controls (right side)
    final teamB = Team.b;
    final playerB = PlayerId.fromTeamAndId(teamB, 'keyboard_player_b');
    PaddleAction actionB = PaddleAction.none;

    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      actionB = PaddleAction.left;
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      actionB = PaddleAction.right;
    }

    networkBridge.sendAction(teamB.id, playerB.id, actionB);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) {
      return;
    }
    timeProvider.updateTime(dt);

    // Update distance tracking for each team
    for (int teamId = 0; teamId < nTeams; teamId++) {
      if (teamId < worlds.length) {
        final world = worlds[teamId];
        // final team = Team.fromId(teamId);
        if (world.ball.isMounted) {
          final ballHeight = world.ball.position.y;
          distanceTracker.updateBallPosition(teamId, ballHeight);

          // Update tournament manager with current distances
          final distance = distanceTracker.getTeamDistance(teamId);
          tournamentManager.updateTeamDistance(teamId, distance);

          // Debug logging (remove after testing)
          // if (distance > 0.1) {
          //   appLog.info(
          //     '${team.shortName} - Ball height: $ballHeight, Distance: ${distance.toStringAsFixed(1)}m',
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

  /// Reload settings from storage and update components
  void _reloadSettings() {
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
  void reloadSettings() {
    _reloadSettings();
  }

  @override
  void onRemove() {
    // Clean up resources
    for (final controller in worldControllers) {
      controller.dispose();
    }
    networkBridge.dispose();
    actionManager.dispose();
    super.onRemove();
  }
}
