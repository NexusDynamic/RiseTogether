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
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/net/network_bridge.dart';
import 'package:rise_together/src/ui/in_game_ui.dart';
import 'package:rise_together/src/settings/app_settings.dart';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/game/world_controller.dart';
import 'rise_together_world.dart';

/// A provider for tracking the time passed in the game.
class TimeProvider extends ChangeNotifier {
  double _timePassed = 0.0;

  double get timePassed => _timePassed;

  void updateTime(double dt) {
    _timePassed += dt;
    notifyListeners();
  }

  String get formattedTime {
    final minutes = (_timePassed / 60).floor().toString().padLeft(2, '0');
    final seconds = (_timePassed % 60).floor().toString().padLeft(2, '0');
    final ms = ((_timePassed % 1) * 100).floor().toString().padLeft(2, '0');
    return '$minutes:$seconds:$ms';
  }
}

class RiseTogetherGame extends Forge2DGame
    with KeyboardEvents, SingleGameInstance, AppLogging, AppSettings {
  final int nTeams = 2;
  late final RouterComponent router;
  final TimeProvider timeProvider = TimeProvider();

  final List<RiseTogetherWorld> worlds = [];
  final List<CameraComponent> cameras = [];
  final List<WorldController> worldControllers = [];

  late final ActionStreamManager actionManager;
  late final NetworkBridge networkBridge;

  final isGameOver = false;

  final RiseTogetherLevel level;
  final bool useLocalNetwork;

  RiseTogetherGame({this.level = const Level1(), this.useLocalNetwork = true})
    : super(gravity: Vector2.zero(), zoom: 10);

  List<Forge2DWorld> _buildWorlds() {
    for (int i = 0; i < nTeams; i++) {
      final world = RiseTogetherWorld(level: level);
      worlds.add(world);
    }
    return worlds;
  }

  RectangleComponent viewportRimGenerator(Vector2 viewportSize) =>
      RectangleComponent(size: viewportSize, anchor: Anchor.topLeft)
        ..paint.color = Color.fromARGB(255, 0, 200, 255)
        ..paint.strokeWidth = 2.0
        ..paint.style = PaintingStyle.stroke;

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
                ..add(viewportRimGenerator(viewportSize)),
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

    appLog.fine('Adding overlay');
    overlays.add(InGameUI.overlayID, priority: 1);
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
    // For testing, send actions for team 0 (left side)

    String testPlayerId = 'keyboard_player_1';
    int testTeamId = 0;
    PaddleAction action = PaddleAction.none;

    if (keysPressed.contains(LogicalKeyboardKey.keyA)) {
      action = PaddleAction.left;
    } else if (keysPressed.contains(LogicalKeyboardKey.keyD)) {
      action = PaddleAction.right;
    }

    networkBridge.sendAction(testTeamId, testPlayerId, action);

    testPlayerId = 'keyboard_player_2';
    testTeamId = 1;
    action = PaddleAction.none;
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      action = PaddleAction.left;
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      action = PaddleAction.right;
    }

    networkBridge.sendAction(testTeamId, testPlayerId, action);

    // Send action through network bridge (which will route to local stream for testing)
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) {
      return;
    }
    timeProvider.updateTime(dt);
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
