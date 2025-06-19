import 'package:rise_together/main.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

/// Target component.
/// This target will be a decorated circle which the player
/// needs to navigate the ball to.
///
/// It can also be used to create a void/obstacle target, that
/// will fail the level if the ball collides with it.

class Target extends BodyComponent<RiseTogetherGame> with ContactCallbacks {
  final double radius;
  final bool isFatal;
  final Vector2 pos;

  Target(this.radius, this.pos, {this.isFatal = false, super.paint});

  @override
  Body createBody() {
    final shape = CircleShape()..radius = radius;
    final fixtureDef = FixtureDef(shape, friction: 0.3);
    final bodyDef = BodyDef(userData: this, position: pos);

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }
}
