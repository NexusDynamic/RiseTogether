import 'package:rise_together/main.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

class Paddle extends BodyComponent<RiseTogetherGame> {
  final Vector2 _start;
  final double _w;
  final double _h;
  final Vector2 _impulseOriginLeft;
  final Vector2 _impulseOriginRight;
  final int participants = 1;

  double pressedLeft = 0;
  double pressedRight = 0;

  Paddle(this._start, _end)
    : _w = max((_end.x - _start.x) / 2, 0.5), // Ensure minimum width
      _h = max((_end.y - _start.y) / 2, 0.5), // Ensure minimum height
      _impulseOriginLeft = Vector2(_start.x - (_end.x - _start.x) / 4, 0),
      _impulseOriginRight = Vector2(_end.x + (_end.x - _start.x) / 4, 0);

  // Helper function to ensure we have a minimum value
  static double max(double a, double b) => a > b ? a : b;

  @override
  Body createBody() {
    Log.log.fine('Creating paddle body with w: $_w, h: $_h');

    final shape = PolygonShape()..setAsBoxXY(_w, _h);

    final fixtureDef = FixtureDef(shape, friction: 1.0, density: 10.0);
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: Vector2(_start.x + _w, _start.y),
      gravityOverride: Vector2(0, 0),
    );

    Log.log.fine('Paddle position: ${bodyDef.position}');
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
          point: _impulseOriginLeft + Vector2(0, body.worldCenter.y),
        );
      } else {
        body.angularVelocity = 0.0;
        body.applyLinearImpulse(
          Vector2(0, -10 * 1 / participants * pressedLeft),
        );
      }
    }
    if (pressedRight > 0) {
      // apply a linear impulse under the paddles bottom right corner of the paddle
      // based on the paddle's current location
      if (body.angle > -1.3) {
        body.applyLinearImpulse(
          Vector2(0, -10 * 1 / participants * pressedRight),
          point: _impulseOriginRight + Vector2(0, body.worldCenter.y),
        );
      } else {
        body.angularVelocity = 0.0;
        body.applyLinearImpulse(
          Vector2(0, -10 * 1 / participants * pressedRight),
        );
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
