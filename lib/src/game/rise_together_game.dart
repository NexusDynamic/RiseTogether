import 'dart:ui' show Color, PaintingStyle;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame/events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show KeyEventResult, KeyEvent;
import 'package:logging/logging.dart' show Level;
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/components/in_game_ui.dart';
import 'package:rise_together/src/settings/app_settings.dart';
import 'rise_together_world.dart';

final Set<LogicalKeyboardKey> validKeys = {
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
};

/// Each player on either team can contribute only one of the following at a
///  time:
///  - paddleLeft: Contributes to the thrust on the left side of the paddle.
///  - paddleRight: Contributes to the thrust on the right side of the paddle.
///  - none: Does not contribute to the paddle's thrust.
enum PlayerContribution { paddleLeft, paddleRight, none }

class PlayerState {
  PlayerContribution currentContribution = PlayerContribution.none;
  PlayerState();
  void reset() {
    currentContribution = PlayerContribution.none;
  }

  void setContribution(PlayerContribution contribution) {
    currentContribution = contribution;
  }
}

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

  final Set<LogicalKeyboardKey> pressedKeySet = {};

  final List<RiseTogetherWorld> worlds = [];
  final List<CameraComponent> cameras = [];

  final isGameOver = false;

  final RiseTogetherLevel level;

  RiseTogetherGame({this.level = const Level1()})
    : super(gravity: Vector2.zero(), zoom: 10);

  List<Forge2DWorld> _buildWorlds() {
    final viewportSize = alignedVector(longMultiplier: 1 / nTeams);
    for (int i = 0; i < nTeams; i++) {
      final world = RiseTogetherWorld(level: level, viewportSize: viewportSize);
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
      cameras.add(
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
          ..viewfinder.zoom = zoomLevel,
      );
    }
    return cameras;
  }

  Future<void> _addPaddles() async {
    for (final camera in cameras) {
      final world = camera.world as RiseTogetherWorld;
      final paddle = world.buildPaddle();
      world.add(paddle);
      final ball = world.buildBall();
      world.add(ball);
      // wait for the paddle to be loaded
      await paddle.loaded;
      appLog.fine('Adding paddle to camera: ${camera.hashCode}');
      camera.follow(paddle);
    }
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
    _clearPressedKeys();
    for (final key in keysPressed) {
      if (!validKeys.contains(key)) {
        continue;
      }
      appLog.fine('Key pressed: $key');
      pressedKeySet.add(key);
    }
    return KeyEventResult.handled;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) {
      return;
    }
    timeProvider.updateTime(dt);
  }

  void _clearPressedKeys() {
    pressedKeySet.clear();
  }
}
