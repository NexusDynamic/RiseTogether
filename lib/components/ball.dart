import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:rise_together/components/target.dart';
import 'package:rise_together/components/wall.dart';
import 'package:rise_together/main.dart';

class Ball extends BodyComponent<RiseTogetherGame> with ContactCallbacks {
  bool isMoving = false;
  bool isRising = false;
  final double radius;

  Ball({required this.radius, super.paint, Vector2? pos})
    : startPosition = pos != null ? Vector2.copy(pos) : Vector2.zero(),
      super();

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      userData: this,
      type: BodyType.dynamic,
      position: startPosition,
      linearDamping: 0.0,
      angularDamping: 0.8,
    );
    final fixtureDef = FixtureDef(
      CircleShape()..radius = radius,
      restitution: 0.2,
      density: 1.0,
      friction: 1.0,
    );

    final sprite = Sprite(game.images.fromCache('ball.png'));
    add(
      SpriteComponent(
        sprite: sprite,
        size: Vector2(2, 2),
        anchor: Anchor.center,
      ),
    );

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  final Vector2 startPosition;

  void move(Vector2 delta) {
    position.add(delta);
  }

  @override
  void update(double dt) {
    if (isMoving) {
      if (isRising) {
        body.applyLinearImpulse(Vector2(0, -400));
        // } else {
        //   if (position.y < startPosition.y) {
        //     body.applyLinearImpulse(Vector2(0, 800));
        //   } else {
        //     position.y = startPosition.y;
        //     isMoving = false;
        //   }
      }
    }
  }

  void startMoving(bool isRising) {
    isMoving = true;
    this.isRising = isRising;
  }

  void stopMoving() {
    isMoving = false;
  }

  @override
  void beginContact(Object other, Contact contact) {
    Log.log.fine('Ball beginContact');
    if (other is Target || other is Wall) {
      Forge2DWorld world = game.world;
      // check if world is subclass of DecoratedWorld
      if (world is DecoratedWorld) {
        world.gameOver = true;
      }
    }
  }
}
