import 'package:flame_forge2d/flame_forge2d.dart';

class Paddle extends BodyComponent {
  final Vector2 _start;
  final Vector2 _end;
  int pressedLeft = 0;
  int pressedRight = 0;

  Paddle(this._start, this._end);

  @override
  Body createBody() {
    final shape = PolygonShape()
      ..setAsBoxXY((_end.x - _start.x) / 2, (_end.y - _start.y) / 2);

    final fixtureDef = FixtureDef(shape, friction: 1.0, density: 10.0);
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: Vector2(camera.visibleWorldRect.center.dx, _start.y),
      gravityOverride: Vector2(0, 0),
    );

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void update(double dt) {
    if (pressedLeft > 0) {
      // apply a linear impulse under the paddles bottom left corner of the paddle
      // based on the paddle's current location
      body.applyLinearImpulse(Vector2(0, -10), point: _start);
    }
    if (pressedRight > 0) {
      // apply a linear impulse under the paddles bottom right corner of the paddle
      // based on the paddle's current location
      body.applyLinearImpulse(Vector2(0, -10), point: _end);
    }
  }

  void pressLeft() {
    pressedLeft++;
  }

  void releaseLeft() {
    // pressedLeft--;
    // temp
    pressedLeft = 0;
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0.0;
  }

  void pressRight() {
    pressedRight++;
  }

  void releaseRight() {
    // pressedRight--;
    // temp
    pressedRight = 0;
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0.0;
  }
}
