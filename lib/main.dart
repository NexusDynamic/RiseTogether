import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/rendering.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide Vector2;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'components/ball.dart';
import 'components/wall.dart';
import 'components/paddle.dart';
import 'components/target.dart';
import 'config.dart';
import 'package:flame/components.dart' hide Timer;
import 'package:flutter/material.dart' hide Route;
import 'package:logging/logging.dart';
import 'package:liblsl/lsl.dart';
// ignore: implementation_imports @TODO: export this in the library
import 'package:liblsl/src/lsl/isolated_outlet.dart' show LSLIsolatedOutlet;
// ignore: implementation_imports @TODO: export this in the library
import 'package:liblsl/src/lsl/isolated_inlet.dart' show LSLIsolatedInlet;
import 'dart:async';
import 'dart:math';
//import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';

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

// https://docs.flame-engine.org/latest/flame/collision_detection.html
// might be worth considering if the two panels require individual collision detection
class RiseTogetherGame extends Forge2DGame
    with SingleGameInstance, HasKeyboardHandlerComponents {
  late final RouterComponent router;
  String participantId = Util.getRandomString(10);
  late LSLIsolatedOutlet outlet;
  late LSLStreamInfo streamInfo;
  LSLIsolatedInlet? inlet;
  MethodChannel? rtNetworkingChannel;

  static Future<void> pushDiscovery(LSLIsolatedOutlet o) async {
    // Push discovery sample to the outlet
    int sampleCount = 0;
    while (sampleCount < 10) {
      await Future.delayed(const Duration(milliseconds: 100));
      o.pushSample([9]);
      sampleCount++;
      Log.log.fine('Pushed discovery sample $sampleCount to outlet');
    }
  }

  @override
  void onLoad() async {
    await super.onLoad();
    if (defaultTargetPlatform == TargetPlatform.android) {
      // get multicast lock
      if (rtNetworkingChannel == null) {
        rtNetworkingChannel = MethodChannel(
          'com.zeyus.RiseTogether/Networking',
        );
        try {
          await rtNetworkingChannel!.invokeMethod('acquireMulticastLock');
          Log.log.fine('acquireMulticastLock: success');
        } on PlatformException catch (e) {
          Log.log.severe('Failed to acquire multicast lock: ${e.message}');
        }
      }
    }
    // Initialize the LSL library
    streamInfo = await LSL.createStreamInfo(
      streamName: 'TapEvents',
      streamType: LSLContentType.markers,
      channelFormat: LSLChannelFormat.int8,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      sourceId: 'client-$participantId',
    );
    outlet = await LSL.createOutlet(streamInfo: streamInfo);
    // Push a discovery sample to the outlet
    pushDiscovery(outlet);
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

  @override
  void onDispose() {
    // Dispose of the LSL outlet (@note: not called on Hot Reload/Restart)
    outlet.destroy();
    inlet?.destroy();
    streamInfo.destroy();
    Log.log.fine('RiseTogetherGame disposed');
    // release multicast lock

    try {
      rtNetworkingChannel?.invokeMethod('releaseMulticastLock');
      Log.log.fine('releaseMulticastLock: success');
    } on PlatformException catch (e) {
      Log.log.severe('Failed to release multicast lock: ${e.message}');
    }
    super.onDispose();
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
      _button2 = RoundedButton(
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
            for (final stream in streams) {
              Log.log.fine('Found stream: ${stream.streamName}');
              if (stream.hostname != 'localhost') {
                game.inlet = await LSL.createInlet(streamInfo: stream);
              }
            }
            streamInfoText =
                'Found streams:\n${streams.map((stream) => '${stream.streamName} (${stream.sourceId}: ${stream.hostname})').join('\n')}';
            _streamInfo.text = streamInfoText;
          }
        },
        color: const Color(0xffadde6c),
        borderColor: const Color(0xffedffab),
      ),
      // stream info text
      _streamInfo = TextComponent(
        text: streamInfoText,
        textRenderer: TextPaint(
          style: const TextStyle(fontSize: 20, color: Color(0xFFC8FFF5)),
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
  late final RoundedButton _button1;
  late final RoundedButton _button2;
  late final TextComponent _streamInfo;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _logo.position = Vector2(size.x / 2, size.y / 3);
    _button1.position = Vector2(size.x / 2, _logo.y + 80);
    _button2.position = Vector2(size.x / 2, _button1.y + 80);
    _participantId.position = Vector2(size.x / 2, _button2.y + 80);
    _streamInfo.position = Vector2(size.x / 2, _participantId.y + 80);
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
    with HasGameRef<RiseTogetherGame>, TapCallbacks, DragCallbacks {
  late final RouterComponent router;
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
    // timer = Timer.periodic(
    //   const Duration(milliseconds: 10),
    //   pushSample,
    // );
    Log.log.fine('LevelPage onLoad - Timer started');
  }

  @override
  void onMount() {
    gameOver = false;
    Ball ball = Ball(
      radius: Config.ballRadius,
      paint: Paint()..color = const Color(0xFFFF0000),
      pos: ballPos,
    );
    // ball.anchor = Anchor.center;

    paddle = Paddle(paddlePos1, paddlePos2);

    Target target = Target(
      Config.ballRadius * 3,
      targetPos,
      paint: Paint()..color = const Color(0xFFFF0000),
    );
    List<Component> walls = createBoundaries();
    addAll([ball, paddle!, target, ...walls]);

    // timer ??= Timer.periodic(
    //   const Duration(milliseconds: 10),
    //   pushSample,
    // );
    Log.log.fine('LevelPage onMount - Timer started');
    super.onMount();
  }

  Future<void> pullSampleAndUpdate() async {
    if (game.inlet == null) {
      return;
    }
    final sample = await game.inlet!.pullSample();
    if (sample.length > 0) {
      _inputStream.text = 'Input stream: ${sample[0]}';
    }
  }

  Future<void> pushSampleAndUpdate(int value) async {
    game.outlet.pushSample([value]);
    _outputStream.text = 'Input stream: $value';
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
    // Optional based on your game needs.
    Log.log.fine('LevelPage onRemove');
    // timer?.cancel();
    // timer = null;
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
