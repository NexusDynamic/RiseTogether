import 'package:flame/components.dart' hide Matrix4;
import 'package:flame/flame.dart';
import 'package:flame/image_composition.dart' hide Matrix4;
import 'package:flame/layers.dart';
import 'package:flame/parallax.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/cupertino.dart' hide Image;
import 'package:rise_together/src/attributes/resetable.dart';
import 'package:rise_together/src/attributes/team_color_provider.dart';
import 'package:rise_together/src/game/world_controller.dart';
import 'package:rise_together/src/models/team_context.dart';
import 'package:rise_together/src/components/ball.dart';
import 'package:rise_together/src/components/wall.dart';
import 'package:rise_together/src/models/team.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/settings/app_settings.dart';
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

class Level2 extends RiseTogetherLevel {
  @override
  final double verticalMultiplier = 15.0; // Taller level for more challenge
  const Level2();
}

class BackgroundLayer extends PreRenderedLayer {
  final RiseTogetherLevel level;

  BackgroundLayer(this.level);

  @override
  void drawLayer() {
    // Add gradient background
    final rect = Rect.fromLTWH(
      -level.horizontalWidth / 2,
      -level.horizontalWidth * level.verticalMultiplier,
      level.horizontalWidth,
      level.horizontalWidth * level.verticalMultiplier,
    );
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      // cool to warm
      colors: [
        const Color.fromARGB(255, 55, 0, 0),
        const Color.fromARGB(255, 17, 17, 54),
      ],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.lighten;
    canvas.drawRect(rect, paint);
  }
}

class RiseTogetherWorld extends Forge2DWorld
    with
        HasGameReference<RiseTogetherGame>,
        AppLogging,
        AppSettings,
        TeamColorProvider,
        Resetable {
  final RiseTogetherLevel level;
  late final ParallaxComponent parallax;
  late CameraComponent _worldCamera;
  late Ball ball;
  late Paddle paddle;
  late final Image image;
  final TeamDisplayPosition pos;
  final BackgroundLayer bgLayer;
  bool _isInitialized = false;
  WorldController get controller {
    if (!_isInitialized) {
      throw StateError(
        'WorldController not set for RiseTogetherWorld. '
        'Call setWorldController() after creating the world.',
      );
    }
    return _controller;
  }

  late WorldController _controller;

  /// Current team context providing consolidated team information
  TeamContext? _teamContext;

  /// Text component showing team name (stored for updates)
  TextComponent? _teamTextComponent;

  RiseTogetherWorld({
    required this.level,
    required this.pos,
    WorldController? controller,
  }) : bgLayer = BackgroundLayer(level),
       super(gravity: Vector2.zero());

  void setWorldController(WorldController controller) {
    _isInitialized = true;
    _controller = controller;
  }

  void setWorldCamera(CameraComponent camera) {
    _worldCamera = camera;
  }

  CameraComponent get worldCamera => _worldCamera;

  /// Set the team context for this world
  void updateTeamContext(TeamContext teamContext) {
    _teamContext = teamContext;
    appLog.fine('Team context set for world: ${teamContext.toString()}');
    // Update any existing visual elements that depend on team colors
    _updateTeamColors();
  }

  /// Get current team context
  TeamContext? get teamContext => _teamContext;

  /// Update visual elements with current team colors
  void _updateTeamColors() {
    // Update team text component if it exists
    if (_teamTextComponent != null) {
      _teamTextComponent!.text = _getTeamDisplayText();
      _teamTextComponent!.textRenderer = TextPaint(
        style: TextStyle(
          color: _getTeamDisplayColor(),
          fontSize: 1,
          shadows: [
            Shadow(
              offset: Offset(0.05, 0.05),
              blurRadius: 0.8,
              color: Color.fromARGB(148, 0, 0, 0),
            ),
          ],
        ),
      );
      appLog.info(
        'Updated team text: "${_teamTextComponent!.text}" with team context: $_teamContext',
      );
    }
  }

  /// Get team display text based on team context
  String _getTeamDisplayText() {
    if (_teamContext != null) {
      return _teamContext!.isPlayerTeam ? 'Your Team' : 'Opponent Team';
    }
    // Fallback to legacy behavior
    return pos == TeamDisplayPosition.left ? 'Your Team' : 'Opponent Team';
  }

  /// Get team display color based on team context
  Color _getTeamDisplayColor() {
    if (_teamContext != null) {
      return _teamContext!.baseColor;
    }
    // Fallback to legacy behavior
    return pos == TeamDisplayPosition.left
        ? getTeamBaseColor(Team.a)
        : getTeamBaseColor(Team.b);
  }

  Future<Paddle> buildPaddle({double widthMultiplier = 1.0}) async {
    final paddleStart = Vector2(
      -0.15 * level.horizontalWidth * widthMultiplier,
      -0.01,
    );
    final paddleEnd = Vector2(
      0.15 * level.horizontalWidth * widthMultiplier,
      -0.01 - 0.02 * level.horizontalWidth,
    );
    paddle = Paddle(this, paddleStart, paddleEnd);
    appLog.info(
      '🔨 Building paddle with widthMultiplier=$widthMultiplier, start: $paddleStart, end: $paddleEnd',
    );

    await add(paddle);
    await paddle.loaded;
    worldCamera.follow(paddle);
    return paddle;
  }

  Future<Ball> buildBall() async {
    ball = Ball(
      this,
      radius: 0.02 * level.horizontalWidth,
      pos: Vector2(
        0.0,
        -0.01 - 0.02 * level.horizontalWidth - 0.02 * level.horizontalWidth,
      ),
    );
    await add(ball);
    await ball.loaded;
    appLog.info(
      '🔨 Building ball with radius: ${0.02 * level.horizontalWidth}',
    );
    return ball;
  }

  @override
  void reset() {
    restartLevel();
  }

  void restartLevel() {
    appLog.fine(
      'Restarting level with horizontal width: ${level.horizontalWidth}.',
    );

    // Clear all player actions for this team when ball hits wall
    game.clearTeamActions(this);

    // Reset ball and paddle to starting positions (world components - reused)
    ball.cancelPendingTransforms();
    ball.stopMovement();
    ball.setPosition(Vector2(0.0, -1));

    // @TODO: this should not be hardcoded, use conf or props
    paddle.cancelPendingTransforms();
    paddle.setAngle(0);
    paddle.setPosition(Vector2(0, -0.01 - 0.01 * level.horizontalWidth));

    // Note: walls and obstacles stay the same for restart (level components)
  }

  @override
  void render(Canvas canvas) {
    // Render background layer first
    super.render(canvas);
    bgLayer.render(canvas);
  }

  /// Load a new level configuration
  /// Ball and paddle (world components) are reused and repositioned
  /// Walls and obstacles (level components) are recreated
  Future<void> loadLevel(RiseTogetherLevel newLevel) async {
    appLog.info('Loading new level: ${newLevel.runtimeType}');

    // Remove level components (walls, obstacles) - will be recreated
    removeWhere((component) => component is Wall);

    // Reposition world components (ball, paddle) for new level
    if (ball.isMounted) {
      final newBallPos = Vector2(
        0.0,
        -0.01 -
            0.02 * newLevel.horizontalWidth -
            0.02 * newLevel.horizontalWidth,
      );
      ball.setPosition(newBallPos);
      ball.stopMovement();
    }

    if (paddle.isMounted) {
      final newPaddlePos = Vector2(0, -0.01 - 0.01 * newLevel.horizontalWidth);
      paddle.setPosition(newPaddlePos);
      paddle.setAngle(0);
    }

    // Create new level components (walls, obstacles)
    final width = newLevel.horizontalWidth;
    final height = newLevel.verticalMultiplier;
    _addBoundaries(width, height);

    appLog.info(
      'Level loaded: ${newLevel.runtimeType} - world components reused, level components recreated',
    );
  }

  void _addBoundaries(double width, double height) {
    final List<Wall> walls = [
      Wall(
        this,
        Vector2(-width / 2, 0),
        Vector2(width / 2, 1),
        isFatal: false,
        usePolygon: true,
        image: image,
        paint: Paint()
          ..color = const Color.fromARGB(255, 71, 71, 71)
          ..style = PaintingStyle.fill,
      ),
      Wall(
        this,
        Vector2(width / 2, 0),
        Vector2(width / 2 + 0.01, -height),
        isFatal: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 0, 255, 51)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
      Wall(
        this,
        Vector2(width / 2, -height),
        Vector2(-width / 2, -height - 0.01),
        isFatal: false,
        paint: Paint()
          ..color = const Color.fromARGB(255, 0, 128, 255)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.01 * width,
      ),
      Wall(
        this,
        Vector2(-width / 2, -height),
        Vector2(-0.01 + -width / 2, 0),
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

    _teamTextComponent = TextComponent(
      text: _getTeamDisplayText(),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: TextStyle(
          color: _getTeamDisplayColor(),
          fontSize: 1,
          shadows: [
            Shadow(
              offset: Offset(0.05, 0.05),
              blurRadius: 0.8,
              color: Color.fromARGB(148, 0, 0, 0),
            ),
          ],
        ),
      ),
      position: Vector2(0, 0.1),
      size: Vector2(width, 1),
      scale: Vector2.all(0.1),
    );
    add(_teamTextComponent!);
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    image = await Flame.images.load('ground_floor.png');
    parallax = await game.loadParallaxComponent(
      [
        ParallaxImageData('stars_0.png'),
        ParallaxImageData('stars_1.png'),
        ParallaxImageData('stars_2.png'),
        ParallaxImageData('bg_scaffold.png'),
      ],
      baseVelocity: Vector2(0, 0),
      repeat: ImageRepeat.repeatY,
      fill: LayerFill.width,
      size: Vector2(game.size.x / 2, game.size.y),
      velocityMultiplierDelta: Vector2(0, 5),
    );
    worldCamera.backdrop.add(parallax);
    _addBoundaries(
      level.horizontalWidth,
      level.horizontalWidth * level.verticalMultiplier,
    );
  }
}
