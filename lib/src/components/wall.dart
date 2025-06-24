import 'package:rise_together/main.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

class Wall extends BodyComponent<RiseTogetherGame> with ContactCallbacks {
  final Vector2 _start;
  final Vector2 _end;
  final bool isFatal;

  Wall(this._start, this._end, {this.isFatal = true, super.paint});

  @override
  Body createBody() {
    final shape = EdgeShape()..set(_start, _end);
    final fixtureDef = FixtureDef(shape, friction: 0.3);
    final bodyDef = BodyDef(userData: this, position: Vector2.zero());

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }
}
