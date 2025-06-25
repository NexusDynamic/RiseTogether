import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
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
  final Vector2 viewportSize;

  RiseTogetherWorld({required this.level, required this.viewportSize})
    : super(gravity: Vector2.zero());

  Paddle buildPaddle() {
    final paddleStart = Vector2(-0.1 * level.horizontalWidth, -0.01);
    final paddleEnd = Vector2(
      0.1 * level.horizontalWidth,
      -0.01 - 0.01 * level.horizontalWidth,
    );
    final paddle = Paddle(this, paddleStart, paddleEnd);
    appLog.fine('Building paddle with start: $paddleStart, end: $paddleEnd.');
    return paddle;
  }

  Ball buildBall() {
    final ball = Ball(
      this,
      radius: 0.01 * level.horizontalWidth,
      pos: Vector2(0.0, -0.02 - 0.01 * level.horizontalWidth),
    );
    return ball;
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
  void onLoad() {
    super.onLoad();
    _addBoundaries(
      level.horizontalWidth,
      level.horizontalWidth * level.verticalMultiplier,
    );
  }
}
