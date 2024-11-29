import 'package:flame_forge2d/flame_forge2d.dart';

class Paddle extends BodyComponent {
  final Vector2 _start;
  final Vector2 _end;
  final double _w;
  final double _h;
  final Vector2 _impulseOriginLeft;
  final Vector2 _impulseOriginRight;
  final int participants = 1;
  double pressedLeft = 0;
  double pressedRight = 0;
  Vector2 pos = Vector2.zero();

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
      type: BodyType.kinematic,
      position: Vector2(camera.visibleWorldRect.center.dx, _start.y),
      gravityOverride: Vector2(0, 0),
    );
    pos = bodyDef.position;
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void update(double dt) {
    // body.fixtures.first.shape.computeAABB(, body.transform, 0);
    // final aabb = body.fixtures.first.getAABB(0);
    // aabb.extents
    if (pressedLeft + pressedRight < 1) {
      return;
    }

    // final center = pos +
    //     Vector2(
    //         _w *
    //             (1 / participants * pressedLeft -
    //                 1 / participants * pressedRight),
    //         0);
    // body.setTransform(center, body.angle);
    if (pressedLeft >= 1) {
      // lift up the left side of the paddle by pressedLeft * 5 degrees / second
      body.angularVelocity = pressedLeft * 15 * dt;
      body.linearVelocity = Vector2(0, -10 * 1 / participants * pressedLeft);
    }
    if (pressedRight >= 1) {
      // lift up the right side of the paddle by pressedRight * 5 degrees / second
      body.angularVelocity = -pressedRight * 15 * dt;
      body.linearVelocity = Vector2(0, -10 * 1 / participants * pressedRight);
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
