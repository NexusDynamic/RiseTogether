import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/rendering.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide Vector2;
import 'components/ball.dart';
import 'components/wall.dart';
import 'components/paddle.dart';
import 'components/target.dart';
import 'config.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:logging/logging.dart';
//import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';

// Log singleton
class Log {
  static final Logger _log = Logger('RiseTogetherGame');

  static Logger get log => _log;
}

// https://docs.flame-engine.org/latest/flame/collision_detection.html
// might be worth considering if the two panels require individual collision detection
class RiseTogetherGame extends Forge2DGame with SingleGameInstance {
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

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: GameWidget(game: RiseTogetherGame()),
    );
  }
}

class MenuPage extends Component with HasGameReference<RiseTogetherGame> {
  MenuPage() {
    addAll([
      _logo = TextComponent(
        text: 'TITLE'.tr(),
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
  late final RouterComponent router;
  late Rect visibleRect;
  late Vector2 ballPos;
  late Vector2 paddlePos1;
  late Vector2 paddlePos2;
  late Vector2 targetPos;
  Paddle? paddle;

  @override
  void onLoad() async {
    await game.loadSprite('ball.png');
    visibleRect = game.camera.visibleWorldRect;
    game.camera.viewport.add(FpsTextComponent(position: Vector2(15, 10)));
    ballPos = Vector2(visibleRect.center.dx, visibleRect.center.dy);
    paddlePos1 = Vector2(visibleRect.center.dx - 10 * Config.ballRadius,
        visibleRect.bottomLeft.dy - 10);
    paddlePos2 = Vector2(visibleRect.center.dx + 10 * Config.ballRadius,
        visibleRect.bottomLeft.dy - 9);
    targetPos = Vector2(-10, 30);
    super.onLoad();
  }

  @override
  void onMount() {
    gameOver = false;
    Ball ball = Ball(
        radius: Config.ballRadius,
        paint: Paint()..color = const Color(0xFFFF0000),
        pos: ballPos);
    // ball.anchor = Anchor.center;

    paddle = Paddle(
      paddlePos1,
      paddlePos2,
    );

    Target target = Target(Config.ballRadius * 3, targetPos,
        paint: Paint()..color = const Color(0xFFFF0000));
    List<Component> walls = createBoundaries();
    addAll([
      ball,
      paddle!,
      target,
      ...walls,
    ]);
    super.onMount();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameOver) {
      if (children.isEmpty) {
        game.router.pop();
        return;
      }
      removeAll(children);
      return;
    }
  }

  @override
  void onRemove() {
    // Optional based on your game needs.
    Log.log.fine('LevelPage onRemove');
    super.onRemove();
  }

  @override
  void onTapDown(TapDownEvent event) {
    final visibleRect = game.camera.visibleWorldRect;
    if (game.screenToWorld(event.canvasPosition).x < visibleRect.topCenter.dx) {
      paddle!.pressLeft();
    } else {
      paddle!.pressRight();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    paddle!.releaseLeft();
    paddle!.releaseRight();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    final visibleRect = game.camera.visibleWorldRect;

    if (game.screenToWorld(event.canvasPosition).x < visibleRect.topCenter.dx) {
      paddle!.pressLeft();
    } else {
      paddle!.pressRight();
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    paddle!.releaseLeft();
    paddle!.releaseRight();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    paddle!.releaseLeft();
    paddle!.releaseRight();
  }

  List<Component> createBoundaries() {
    final Rect visibleRect = game.camera.visibleWorldRect;
    final Vector2 topLeft = visibleRect.topLeft.toVector2();
    final Vector2 topRight = visibleRect.topRight.toVector2();
    final Vector2 bottomRight = visibleRect.bottomRight.toVector2();
    final Vector2 bottomLeft = visibleRect.bottomLeft.toVector2();
    final Paint paint = Paint()..color = const Color.fromARGB(255, 255, 0, 0);
    return [
      Wall(topLeft, topRight, paint: paint),
      Wall(topRight, bottomRight, paint: paint),
      Wall(bottomLeft, bottomRight, paint: paint),
      Wall(topLeft, bottomLeft, paint: paint),
    ];
  }
}

class DecoratedWorld extends Forge2DWorld with HasTimeScale {
  PaintDecorator? decorator;
  bool gameOver = false;

  @override
  void renderFromCamera(Canvas canvas) {
    if (decorator == null) {
      super.renderFromCamera(canvas);
    } else {
      decorator!.applyChain(super.renderFromCamera, canvas);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await FullScreen.ensureInitialized();
  FullScreen.setFullScreen(true);
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en'), Locale('da')],
      path: 'assets/translations',
      fallbackLocale: Locale('en'),
      startLocale: Locale('da'),
      useOnlyLangCode: true,
      // child: GameWidget(game: RiseTogetherGame()),
      child: App(),
    ),
  );
}
