import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:rise_together/src/attributes/positionable.dart';
import 'package:rise_together/src/components/wall.dart';
import 'package:rise_together/src/game/rise_together_world.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/settings/app_settings.dart';

class Ball extends BodyComponent<RiseTogetherGame>
    with ContactCallbacks, AppLogging, AppSettings, PositionableBodyComponent {
  bool isMoving = false;
  bool isRising = false;
  final double radius;
  @override
  final RiseTogetherWorld world;

  Ball(this.world, {required this.radius, super.paint, Vector2? pos})
    : startPosition = pos ?? Vector2.zero(),
      super();

  @override
  Future<void> onLoad() async {
    appLog.fine(appSettings.toString());
    appLog.fine(
      'Ball onLoad called with radius: $radius, startPosition: $startPosition',
    );
    await super.onLoad();
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      userData: this,
      type: BodyType.dynamic,
      position: startPosition,
      linearDamping: 1.0,
      angularDamping: 0.8,
      gravityOverride: Vector2(0, appSettings['physics.gravity']),
    );
    final fixtureDef = FixtureDef(
      CircleShape()..radius = radius,
      restitution: 0.0,
      density: 5.0,
      friction: 10.0,
    );

    final sprite = Sprite(game.images.fromCache('ball.png'));
    add(
      SpriteComponent(
        sprite: sprite,
        size: Vector2(2 * radius, 2 * radius),
        anchor: Anchor.center,
      ),
    );
    renderBody = false;
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  final Vector2 startPosition;

  @override
  void update(double dt) {
    super.update(dt);
    applyPendingTransforms();
  }

  @override
  void beginContact(Object other, Contact contact) {
    appLog.fine('Ball beginContact');
    if (other is Wall) {
      world.restartLevel();
    }
  }
}
