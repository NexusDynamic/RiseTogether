import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/widgets.dart';
import 'package:flame/events.dart';
import 'components/ball.dart';
import 'components/wall.dart';
import 'components/paddle.dart';
import 'config.dart';
import 'package:flame/components.dart';
import 'package:flame_forge2d/forge2d_game.dart';

class RiseTogetherGame extends Forge2DGame with TapDetector, PanDetector {
  late Ball ball;
  late Paddle paddle;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await loadSprite('ball.png');
    final visibleRect = camera.visibleWorldRect;
    camera.viewport.add(FpsTextComponent(position: Vector2(15, 10)));
    ball = Ball(
        radius: Config.ballRadius,
        paint: Paint()..color = const Color(0xFFFF0000),
        pos: Vector2(visibleRect.center.dx, visibleRect.center.dy));
    // ball.anchor = Anchor.center;
    paddle = Paddle(
      Vector2(visibleRect.center.dx - 10 * Config.ballRadius,
          visibleRect.bottomLeft.dy - 10),
      Vector2(visibleRect.center.dx + 10 * Config.ballRadius,
          visibleRect.bottomLeft.dy - 9),
    );
    world.add(ball);
    world.add(paddle);
    world.addAll(createBoundaries());
  }

  RiseTogetherGame() : super(gravity: Vector2(0, 15.0));

  @override
  void onTapDown(TapDownInfo info) {
    final visibleRect = camera.visibleWorldRect;

    if (screenToWorld(info.eventPosition.global).x < visibleRect.topCenter.dx) {
      paddle.pressLeft();
    } else {
      paddle.pressRight();
    }
  }

  @override
  void onTapUp(TapUpInfo info) {
    paddle.releaseLeft();
    paddle.releaseRight();
  }

  @override
  void onPanStart(DragStartInfo info) {
    final visibleRect = camera.visibleWorldRect;

    if (screenToWorld(info.eventPosition.global).x < visibleRect.topCenter.dx) {
      paddle.pressLeft();
    } else {
      paddle.pressRight();
    }
  }

  @override
  void onPanEnd(DragEndInfo info) {
    paddle.releaseLeft();
    paddle.releaseRight();
  }

  @override
  void onPanCancel() {
    paddle.releaseLeft();
    paddle.releaseRight();
  }

  List<Component> createBoundaries() {
    final visibleRect = camera.visibleWorldRect;
    final topLeft = visibleRect.topLeft.toVector2();
    final topRight = visibleRect.topRight.toVector2();
    final bottomRight = visibleRect.bottomRight.toVector2();
    final bottomLeft = visibleRect.bottomLeft.toVector2();

    return [
      Wall(topLeft, topRight),
      Wall(topRight, bottomRight),
      Wall(bottomLeft, bottomRight),
      Wall(topLeft, bottomLeft),
    ];
  }
}

void main() {
  runApp(const GameWidget.controlled(gameFactory: RiseTogetherGame.new));
}
