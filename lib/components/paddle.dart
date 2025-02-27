import 'package:rise_together/main.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

class Paddle extends BodyComponent<RiseTogetherGame> {
  final Vector2 _start;
  final Vector2 _end;
  final double _w;
  final double _h;
  final Vector2 _impulseOriginLeft;
  final Vector2 _impulseOriginRight;
  final int participants = 1;

  double pressedLeft = 0;
  double pressedRight = 0;

  Paddle(this._start, this._end)
      : _w = (_end.x - _start.x) / 2,
        _h = (_end.y - _start.y) / 2,
        _impulseOriginLeft = Vector2(_start.x - (_end.x - _start.x) / 4, 0),
        _impulseOriginRight = Vector2(_end.x + (_end.x - _start.x) / 4, 0);

  @override
  Body createBody() {
    final shape = PolygonShape()..setAsBoxXY(_w, _h);

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
    if (pressedLeft + pressedRight < 1) {
      return;
    }
    if (pressedLeft > 0) {
      // apply a linear impulse under the paddles bottom left corner of the paddle
      // based on the paddle's current location
      if (body.angle < 1.3) {
        body.applyLinearImpulse(
            Vector2(0, -10 * 1 / participants * pressedLeft),
            point: _impulseOriginLeft + Vector2(0, body.worldCenter.y));
      } else {
        body.angularVelocity = 0.0;
        body.applyLinearImpulse(
            Vector2(0, -10 * 1 / participants * pressedLeft));
      }
    }
    if (pressedRight > 0) {
      // apply a linear impulse under the paddles bottom right corner of the paddle
      // based on the paddle's current location
      if (body.angle > -1.3) {
        body.applyLinearImpulse(
            Vector2(0, -10 * 1 / participants * pressedRight),
            point: _impulseOriginRight + Vector2(0, body.worldCenter.y));
      } else {
        body.angularVelocity = 0.0;
        body.applyLinearImpulse(
            Vector2(0, -10 * 1 / participants * pressedRight));
      }
    }
  }

  void pressLeft() {
    pressedLeft++;
  }

  void releaseLeft() {
    // pressedLeft--;
    // temp
    pressedLeft = 0;
    body.clearForces();
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
    body.clearForces();
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0.0;
  }
}
