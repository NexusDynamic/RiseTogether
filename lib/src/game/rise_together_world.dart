import 'package:flame/components.dart';
import 'package:flame/parallax.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/cupertino.dart';
import 'package:rise_together/src/components/ball.dart';
import 'package:rise_together/src/components/wall.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'rise_together_game.dart';
import 'package:rise_together/src/components/paddle.dart';

abstract class RiseTogetherLevel {
  final double horizontalWidth = 1.0;
  abstract final double verticalMultiplier;
  const RiseTogetherLevel();
}

class Level1 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 10.0;
  const Level1();
}

class RiseTogetherWorld extends Forge2DWorld
    with HasGameReference<RiseTogetherGame>, AppLogging {
  final RiseTogetherLevel level;
  late final ParallaxComponent parallax;
  late CameraComponent _worldCamera;
  late Ball ball;
  late Paddle paddle;

  RiseTogetherWorld({required this.level}) : super(gravity: Vector2.zero());

  void setWorldCamera(CameraComponent camera) {
    _worldCamera = camera;
  }

  CameraComponent get worldCamera => _worldCamera;

  Paddle buildPaddle() {
    final paddleStart = Vector2(-0.15 * level.horizontalWidth, -0.01);
    final paddleEnd = Vector2(
      0.15 * level.horizontalWidth,
      -0.01 - 0.02 * level.horizontalWidth,
    );
    paddle = Paddle(this, paddleStart, paddleEnd);
    appLog.fine('Building paddle with start: $paddleStart, end: $paddleEnd.');
    return paddle;
  }

  Ball buildBall() {
    ball = Ball(
      this,
      radius: 0.02 * level.horizontalWidth,
      pos: Vector2(0.0, -1),
    );
    return ball;
  }

  void restartLevel() {
    appLog.fine(
      'Restarting level with horizontal width: ${level.horizontalWidth}.',
    );

    // set ball and paddle to starting positions
    ball.setPosition(Vector2(0.0, -1));
    ball.stopMovement();
    // @TODO: this should not be hardcoded, use conf or props
    paddle.setPosition(Vector2(0, -0.01 - 0.01 * level.horizontalWidth));
    paddle.setAngle(0);
  }

  void _addBoundaries(double width, double height) {
    final List<Wall> walls = [
      Wall(
        this,
        Vector2(-width / 2, 0),
        Vector2(width / 2, 0),
        isFatal: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 255, 0, 0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
      Wall(
        this,
        Vector2(width / 2, 0),
        Vector2(width / 2, -height),
        isFatal: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 0, 255, 51)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
      Wall(
        this,
        Vector2(width / 2, -height),
        Vector2(-width / 2, -height),
        isFatal: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 0, 128, 255)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
      Wall(
        this,
        Vector2(-width / 2, -height),
        Vector2(-width / 2, 0),
        isFatal: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 204, 255, 0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
    ];
    appLog.fine('Adding boundaries with width: $width, height: $height.');
    for (final wall in walls) {
      appLog.fine('Adding wall: $wall');
    }
    addAll(walls);
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    parallax = await game.loadParallaxComponent(
      [
        ParallaxImageData('stars_0.png'),
        ParallaxImageData('stars_1.png'),
        ParallaxImageData('stars_2.png'),
      ],
      baseVelocity: Vector2(0, 0),
      repeat: ImageRepeat.repeat,
      velocityMultiplierDelta: Vector2(0, 5),
    );
    worldCamera.backdrop.add(parallax);
    _addBoundaries(
      level.horizontalWidth,
      level.horizontalWidth * level.verticalMultiplier,
    );
  }
}
