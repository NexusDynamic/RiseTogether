import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/rendering.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'components/ball.dart';
import 'components/wall.dart';
import 'components/paddle.dart';
import 'components/target.dart';
import 'config.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:logging/logging.dart';

// Log singleton
class Log {
  static final Logger _log = Logger('RiseTogetherGame');

  static Logger get log => _log;
}

// https://docs.flame-engine.org/latest/flame/collision_detection.html
// might be worth considering if the two panels require individual collision detection
class RiseTogetherGame extends Forge2DGame {
  late final RouterComponent router;

  @override
  void onLoad() async {
    await super.onLoad();
    Log.log.fine('RiseTogetherGame loaded');
    await add(
      router = RouterComponent(
        routes: {
          'home': Route(MenuPage.new),
          'level': WorldRoute(LevelPage.new),
        },
        initialRoute: 'home',
      ),
    );
  }

  RiseTogetherGame() : super(gravity: Vector2(0, 15.0));
}

class MenuPage extends Component with HasGameReference<RiseTogetherGame> {
  MenuPage() {
    addAll([
      _logo = TextComponent(
        text: 'Your Game',
        textRenderer: TextPaint(
          style: const TextStyle(
            fontSize: 64,
            color: Color(0xFFC8FFF5),
            fontWeight: FontWeight.w800,
          ),
        ),
        anchor: Anchor.center,
      ),
      _button1 = RoundedButton(
        text: 'Level 1',
        action: () {
          // log the action
          Log.log.fine('MenuPage, level1 button pressed');
          game.router.pushNamed('level');
        },
        color: const Color(0xffadde6c),
        borderColor: const Color(0xffedffab),
      ),
    ]);
  }

  late final TextComponent _logo;
  late final RoundedButton _button1;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _logo.position = Vector2(size.x / 2, size.y / 3);
    _button1.position = Vector2(size.x / 2, _logo.y + 80);
  }
}

class RoundedButton extends PositionComponent with TapCallbacks {
  RoundedButton({
    required this.text,
    required this.action,
    required Color color,
    required Color borderColor,
    super.position,
    super.anchor = Anchor.center,
  }) : _textDrawable = TextPaint(
          style: const TextStyle(
            fontSize: 20,
            color: Color(0xFF000000),
            fontWeight: FontWeight.w800,
          ),
        ).toTextPainter(text) {
    size = Vector2(150, 40);
    _textOffset = Offset(
      (size.x - _textDrawable.width) / 2,
      (size.y - _textDrawable.height) / 2,
    );
    _rrect = RRect.fromLTRBR(0, 0, size.x, size.y, Radius.circular(size.y / 2));
    _bgPaint = Paint()..color = color;
    _borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = borderColor;
  }

  final String text;
  final void Function() action;
  final TextPainter _textDrawable;
  late final Offset _textOffset;
  late final RRect _rrect;
  late final Paint _borderPaint;
  late final Paint _bgPaint;

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(_rrect, _bgPaint);
    canvas.drawRRect(_rrect, _borderPaint);
    _textDrawable.paint(canvas, _textOffset);
  }

  @override
  void onTapDown(TapDownEvent event) {
    scale = Vector2.all(1.05);
    Log.log.fine('RoundedButton onTapDown');
  }

  @override
  void onTapUp(TapUpEvent event) {
    scale = Vector2.all(1.0);
    Log.log.fine('RoundedButton onTapUp');
    action();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    scale = Vector2.all(1.0);
    Log.log.fine('RoundedButton onTapCancel');
  }
}

class LevelPage extends DecoratedWorld
    with HasGameRef<RiseTogetherGame>, TapCallbacks, DragCallbacks {
  late Ball ball;
  late Paddle paddle;
  late Target target;
  late final RouterComponent router;

  @override
  void onLoad() async {
    await game.loadSprite('ball.png');
    final visibleRect = game.camera.visibleWorldRect;
    game.camera.viewport.add(FpsTextComponent(position: Vector2(15, 10)));
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
    target = Target(Config.ballRadius * 3, Vector2(0, 0),
        paint: Paint()..color = const Color(0xFFFF0000));

    addAll([
      ball,
      paddle,
      target,
      ...createBoundaries(),
    ]);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final visibleRect = game.camera.visibleWorldRect;
    if (game.screenToWorld(event.canvasPosition).x < visibleRect.topCenter.dx) {
      paddle.pressLeft();
    } else {
      paddle.pressRight();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    paddle.releaseLeft();
    paddle.releaseRight();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    final visibleRect = game.camera.visibleWorldRect;

    if (game.screenToWorld(event.canvasPosition).x < visibleRect.topCenter.dx) {
      paddle.pressLeft();
    } else {
      paddle.pressRight();
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    paddle.releaseLeft();
    paddle.releaseRight();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    paddle.releaseLeft();
    paddle.releaseRight();
  }

  List<Component> createBoundaries() {
    final Rect visibleRect = game.camera.visibleWorldRect;
    final Vector2 topLeft = visibleRect.topLeft.toVector2();
    final Vector2 topRight = visibleRect.topRight.toVector2();
    final Vector2 bottomRight = visibleRect.bottomRight.toVector2();
    final Vector2 bottomLeft = visibleRect.bottomLeft.toVector2();

    return [
      Wall(topLeft, topRight),
      Wall(topRight, bottomRight),
      Wall(bottomLeft, bottomRight),
      Wall(topLeft, bottomLeft),
    ];
  }
}

class DecoratedWorld extends Forge2DWorld with HasTimeScale {
  PaintDecorator? decorator;

  @override
  void renderFromCamera(Canvas canvas) {
    if (decorator == null) {
      super.renderFromCamera(canvas);
    } else {
      decorator!.applyChain(super.renderFromCamera, canvas);
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  runApp(GameWidget(game: RiseTogetherGame()));
}
