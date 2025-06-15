import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/rendering.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide Vector2;
import 'package:flutter/services.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'components/ball.dart';
import 'components/wall.dart';
import 'components/paddle.dart';
import 'components/target.dart';
import 'config.dart';
import 'components/split_world.dart';
import 'services/lsl_service.dart';
import 'package:flame/components.dart' hide Timer;
import 'package:flutter/material.dart' hide Route;
import 'package:logging/logging.dart';
import 'package:liblsl/lsl.dart';
import 'dart:async';
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';

// Log singleton
class Log {
  static final Logger _log = Logger('RiseTogetherGame');
  static Logger get log => _log;
}

class Util {
  static String getRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    Random random = Random();
    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }
}

// class RiseTogetherGame extends Forge2DGame
//     with SingleGameInstance, HasKeyboardHandlerComponents {

class RiseTogetherGame extends Forge2DGame
    with SingleGameInstance, HasKeyboardHandlerComponents {
  late final RouterComponent router;
  String participantId = Util.getRandomString(10);
  String teamId = "team1"; // Default team, can be changed
  FlutterMulticastLock multicastLock = FlutterMulticastLock();
  final refreshRateControl = FlutterRefreshRateControl();

  LSLService? lslService;

  @override
  Future<void> onLoad() async {
    // Set the time scale to 1.0 (normal speed)
    camera.viewfinder.anchor = Anchor.topLeft;
    await super.onLoad();

    // Request high refresh rate
    try {
      bool success = await refreshRateControl.requestHighRefreshRate();
      if (success) {
        Log.log.fine('High refresh rate requested successfully.');
      } else {
        Log.log.warning('Failed to enable high refresh rate');
      }
    } catch (e) {
      Log.log.severe('Error: $e');
    }

    // Initialize multicast for Android
    multicastLock
        .acquireMulticastLock()
        .then((value) {
          Log.log.fine('acquireMulticastLock: success');
        })
        .catchError((error) {
          Log.log.severe('Failed to acquire multicast lock: $error');
        });

    // Initialize LSL service
    lslService = LSLService(participantId: participantId, teamId: teamId);
    await lslService!.initialize();

    Log.log.fine('RiseTogetherGame loaded');

    // Setup game routes
    await add(
      router = RouterComponent(
        routes: {
          'home': Route(MenuPage.new),
          'level': WorldRoute(LevelPage.new),
          'split_level': WorldRoute(
            () => SplitScreenLevelPage(
              localTeamId: teamId,
              remoteTeamId: teamId == "team1" ? "team2" : "team1",
            ),
          ),
        },
        initialRoute: 'home',
      ),
    );
  }

  @override
  void onDispose() {
    // Clean up resources
    lslService?.dispose();

    try {
      refreshRateControl.stopHighRefreshRate();
    } catch (e) {
      Log.log.severe('Error: $e');
    }

    multicastLock
        .releaseMulticastLock()
        .then((value) {
          Log.log.fine('releaseMulticastLock: success');
        })
        .catchError((error) {
          Log.log.severe('Failed to release multicast lock: $error');
        });
    Log.log.fine('RiseTogetherGame disposed');
    super.onDispose();
  }

  RiseTogetherGame() : super(gravity: Vector2(0, 15.0));
}

class MenuPage extends Component
    with HasGameReference<RiseTogetherGame>, KeyboardHandler {
  String streamInfoText = 'Stream info';

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
      _participantId = TextComponent(
        text: game.participantId,
        textRenderer: TextPaint(
          style: const TextStyle(fontSize: 20, color: Color(0xFFC8FFF5)),
        ),
        anchor: Anchor.center,
      ),
      _teamSelector = TextComponent(
        text: 'Team: ${game.teamId}',
        textRenderer: TextPaint(
          style: const TextStyle(fontSize: 20, color: Color(0xFFC8FFF5)),
        ),
        anchor: Anchor.center,
      ),
      _button1 = RoundedButton(
        text: 'Single Player Mode',
        action: () {
          Log.log.fine('MenuPage, level1 button pressed');
          game.router.pushNamed('level');
        },
        color: const Color(0xffadde6c),
        borderColor: const Color(0xffedffab),
      ),
      _button2 = RoundedButton(
        text: 'Split Screen Mode',
        action: () {
          Log.log.fine('MenuPage, split screen button pressed');
          game.router.pushNamed('split_level');
        },
        color: const Color(0xffadde6c),
        borderColor: const Color(0xffedffab),
      ),
      _button3 = RoundedButton(
        text: 'Switch Team',
        action: () {
          // Toggle team
          game.teamId = game.teamId == "team1" ? "team2" : "team1";
          _teamSelector.text = 'Team: ${game.teamId}';

          // Reinitialize LSL service with new team ID
          game.lslService?.dispose();
          game.lslService = LSLService(
            participantId: game.participantId,
            teamId: game.teamId,
          );
          game.lslService!.initialize();
          Log.log.fine('Switched to ${game.teamId}');
        },
        color: const Color(0xffadde6c),
        borderColor: const Color(0xffedffab),
      ),
      _button4 = RoundedButton(
        text: 'Find streams',
        action: () async {
          // log the action
          Log.log.fine('MenuPage, find streams button pressed');
          // find streams
          final List<LSLStreamInfo> streams = await LSL.resolveStreams(
            waitTime: 5.0,
            maxStreams: 10,
          );
          if (streams.isNotEmpty) {
            // update the stream info text with each stream name
            Log.log.fine('Found streams: ${streams.length}');

            streamInfoText =
                'Found streams:\n${streams.map((stream) => '${stream.streamName} (${stream.sourceId}: ${stream.hostname})').join('\n')}';
            _streamInfo.text = streamInfoText;
          }
        },
        color: const Color(0xffadde6c),
        borderColor: const Color(0xffedffab),
      ),
      _streamInfo = TextComponent(
        text: streamInfoText,
        textRenderer: TextPaint(
          style: const TextStyle(fontSize: 16, color: Color(0xFFC8FFF5)),
        ),
        anchor: Anchor.center,
      ),
    ]);
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // put typing in the text field
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.backspace &&
          _participantId.text.isNotEmpty) {
        _participantId.text = _participantId.text.substring(
          0,
          _participantId.text.length - 1,
        );
      } else {
        _participantId.text += event.logicalKey.keyLabel;
      }
      game.participantId = _participantId.text;
      return true;
    }
    return false;
  }

  late final TextComponent _logo;
  late final TextComponent _participantId;
  late final TextComponent _teamSelector;
  late final RoundedButton _button1;
  late final RoundedButton _button2;
  late final RoundedButton _button3;
  late final RoundedButton _button4;
  late final TextComponent _streamInfo;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _logo.position = Vector2(size.x / 2, size.y / 6);
    _participantId.position = Vector2(size.x / 2, _logo.y + 60);
    _teamSelector.position = Vector2(size.x / 2, _participantId.y + 40);
    _button1.position = Vector2(size.x / 2, _teamSelector.y + 60);
    _button2.position = Vector2(size.x / 2, _button1.y + 60);
    _button3.position = Vector2(size.x / 2, _button2.y + 60);
    _button4.position = Vector2(size.x / 2, _button3.y + 60);
    _streamInfo.position = Vector2(size.x / 2, _button4.y + 60);
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
    _borderPaint =
        Paint()
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
    with HasGameReference<RiseTogetherGame>, TapCallbacks, DragCallbacks {
  late Rect visibleRect;
  late Vector2 ballPos;
  late Vector2 paddlePos1;
  late Vector2 paddlePos2;
  late Vector2 targetPos;
  Timer? timer;
  Paddle? paddle;
  late TextComponent _inputStream;
  late TextComponent _outputStream;

  @override
  void onLoad() async {
    await game.loadSprite('ball.png');
    visibleRect = game.camera.visibleWorldRect;
    game.camera.viewfinder.position = Vector2(
      visibleRect.center.dx,
      visibleRect.center.dy,
    );
    game.camera.viewport.add(FpsTextComponent(position: Vector2(15, 10)));
    // add input textcomponent
    _inputStream = TextComponent(
      text: 'Input stream',
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 20, color: Color(0xFFC8FFF5)),
      ),
      anchor: Anchor.topLeft,
    );
    _inputStream.position = Vector2(game.camera.viewport.size.x / 2, 15);
    game.camera.viewport.add(_inputStream);
    // add output textcomponent
    _outputStream = TextComponent(
      text: 'Output stream',
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 20, color: Color(0xFFC8FFF5)),
      ),
      anchor: Anchor.bottomLeft,
    );
    _outputStream.position = Vector2(10, game.camera.viewport.size.y - 10);
    game.camera.viewport.add(_outputStream);

    ballPos = Vector2(visibleRect.center.dx, visibleRect.center.dy);
    paddlePos1 = Vector2(
      visibleRect.center.dx - 10 * Config.ballRadius,
      visibleRect.bottomLeft.dy - 10,
    );
    paddlePos2 = Vector2(
      visibleRect.center.dx + 10 * Config.ballRadius,
      visibleRect.bottomLeft.dy - 9,
    );
    targetPos = Vector2(-10, 30);
    super.onLoad();
    Log.log.fine('LevelPage onLoad');
  }

  @override
  void onMount() async {
    gameOver = false;
    Ball ball = Ball(
      radius: Config.ballRadius,
      paint: Paint()..color = const Color(0xFFFF0000),
      pos: ballPos,
    );

    paddle = Paddle(paddlePos1, paddlePos2);

    Target target = Target(
      Config.ballRadius * 3,
      targetPos,
      paint: Paint()..color = const Color(0xFFFF0000),
    );
    List<Component> walls = createBoundaries();
    await addAll([ball, paddle!, target, ...walls]);

    Log.log.fine('LevelPage onMount');
    super.onMount();
  }

  Future<void> pullSampleAndUpdate() async {
    if (game.lslService == null) {
      return;
    }
  }

  Future<void> pushSampleAndUpdate(int value) async {
    // Use the LSL service to send player input
    if (game.lslService != null) {
      String input = value == -1 ? "left" : (value == 1 ? "right" : "none");
      game.lslService!.sendPlayerInput(input);
      _outputStream.text = 'Output: $input';
    }
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
    pullSampleAndUpdate();
  }

  @override
  void onRemove() {
    Log.log.fine('LevelPage onRemove');
    super.onRemove();
  }

  @override
  void onTapDown(TapDownEvent event) {
    final visibleRect = game.camera.visibleWorldRect;
    if (game.screenToWorld(event.canvasPosition).x < visibleRect.topCenter.dx) {
      pushSampleAndUpdate(-1);
      paddle!.pressLeft();
    } else {
      pushSampleAndUpdate(1);
      paddle!.pressRight();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    pushSampleAndUpdate(0);
    paddle!.releaseLeft();
    paddle!.releaseRight();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    final visibleRect = game.camera.visibleWorldRect;

    if (game.screenToWorld(event.canvasPosition).x < visibleRect.topCenter.dx) {
      pushSampleAndUpdate(-1);
      paddle!.pressLeft();
    } else {
      pushSampleAndUpdate(1);
      paddle!.pressRight();
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    pushSampleAndUpdate(0);
    paddle!.releaseLeft();
    paddle!.releaseRight();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    pushSampleAndUpdate(0);
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
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await EasyLocalization.ensureInitialized();
  await FullScreen.ensureInitialized();
  await WakelockPlus.enable();

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
      useFallbackTranslations: true,
      child: App(),
    ),
  );
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
