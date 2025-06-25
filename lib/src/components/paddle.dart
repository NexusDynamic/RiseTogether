import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/log_service.dart';

class Paddle extends BodyComponent<RiseTogetherGame> with AppLogging {
  final Vector2 _start;
  final double _w;
  final double _h;
  final Vector2 _impulseOriginLeft;
  final Vector2 _impulseOriginRight;
  final int participants = 1;
  @override
  final Forge2DWorld world;

  double pressedLeft = 0;
  double pressedRight = 0;

  Paddle(this.world, this._start, _end)
    : _w = (_end.x - _start.x) / 2, // Ensure minimum width
      _h = (_end.y - _start.y) / 2, // Ensure minimum height
      _impulseOriginLeft = Vector2(_start.x - (_end.x - _start.x) / 8, 0),
      _impulseOriginRight = Vector2(_end.x + (_end.x - _start.x) / 8, 0);

  // Helper function to ensure we have a minimum value
  static double max(double a, double b) => a > b ? a : b;

  @override
  Body createBody() {
    appLog.fine('Creating paddle body with w: $_w, h: $_h');

    final shape = PolygonShape()..setAsBoxXY(_w, _h);

    final fixtureDef = FixtureDef(shape, friction: 1.0, density: 10.0);
    final bodyDef = BodyDef(
      type: BodyType.kinematic,
      position: Vector2(_start.x + _w, _start.y),
      gravityOverride: Vector2(0, 0),
    );

    appLog.fine('Paddle position: ${bodyDef.position}');
    appLog.fine('World: ${world.hashCode}');
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.pressedKeySet.isEmpty) {
      body.clearForces();
      body.linearVelocity = Vector2.zero();
      body.angularVelocity = 0.0;
      return;
    }
    if (game.pressedKeySet.contains(LogicalKeyboardKey.arrowLeft)) {
      pressedLeft = 1;
      // apply a linear impulse under the paddles bottom left corner of the paddle
      // based on the paddle's current location
      // body.applyLinearImpulse(
      //   Vector2(0, -0.0001 * 1 / participants * pressedLeft),
      //   point: _impulseOriginLeft + Vector2(0, body.worldCenter.y),
      // );
    } else {
      pressedLeft = 0;
    }
    if (game.pressedKeySet.contains(LogicalKeyboardKey.arrowRight)) {
      pressedRight = 1;
      // apply a linear impulse under the paddles bottom right corner of the paddle
      // based on the paddle's current location
      // body.applyLinearImpulse(
      //   Vector2(0, -0.0001 * 1 / participants * pressedRight),
      //   point: _impulseOriginRight + Vector2(0, body.worldCenter.y),
      // );
    } else {
      pressedRight = 0;
    }
    // calulate rotation amount
    double rotationAmount = 0.0;
    final degreesPerSecond = 1.0;
    if (pressedLeft > 0) {
      rotationAmount += degreesPerSecond * dt * pressedLeft;
    }
    if (pressedRight > 0) {
      rotationAmount -= degreesPerSecond * dt * pressedRight;
    }

    // calculate upward velocity
    final upwardVelocity = -1.0 * (pressedLeft + pressedRight) / participants;

    // apply the rotation and upward velocity
    body.setTransform(body.position, body.angle + rotationAmount);
    body.linearVelocity = Vector2(0.0, upwardVelocity);

    if (body.angle < -1.3) {
      body.angularVelocity = 0.0;
      body.setTransform(body.position, -1.3);
    } else if (body.angle > 1.3) {
      body.angularVelocity = 0.0;
      body.setTransform(body.position, 1.3);
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
