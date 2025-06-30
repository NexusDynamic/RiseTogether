import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/cupertino.dart';
import 'package:rise_together/src/attributes/positionable.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/log_service.dart';

class Paddle extends BodyComponent<RiseTogetherGame>
    with AppLogging, PositionableBodyComponent {
  final Vector2 _start;
  final double _w;
  final double _h;

  /// Position valuenotifier for paddle
  final ValueNotifier<double> positionNotifier = ValueNotifier(0.0);
  @override
  final Forge2DWorld world;

  double thrustLeft = 0.0;
  double thrustRight = 0.0;

  Paddle(this.world, this._start, _end)
    : _w = (_end.x - _start.x).abs() / 2, // Ensure minimum width
      _h = (_end.y - _start.y).abs() / 2; // Ensure minimum height

  @override
  Body createBody() {
    appLog.fine('Creating paddle body with w: $_w, h: $_h');

    final shape = EdgeShape()
      ..set(Vector2(_start.x, _start.y), Vector2(_start.x + 2 * _w, _start.y));

    final fixtureDef = FixtureDef(shape, friction: 20.0, density: 1.0);
    final bodyDef = BodyDef(
      type: BodyType.kinematic,
      position: Vector2(_start.x + _w, _start.y),
      gravityOverride: Vector2(0, 0),
    );
    paint = Paint()
      ..color = const Color.fromARGB(255, 0, 187, 255)
      ..style = PaintingStyle.stroke
      ..strokeWidth = polygonRadius * 1.5;
    positionNotifier.value = bodyDef.position.y;
    appLog.fine('Paddle position: ${bodyDef.position}');
    appLog.fine('World: ${world.hashCode}');
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  /// Set thrust values from action system
  double setThrust(double leftThrust, double rightThrust) {
    thrustLeft = leftThrust;
    thrustRight = rightThrust;
    return thrustLeft + thrustRight;
  }

  @override
  void update(double dt) {
    super.update(dt);

    applyPendingTransforms();

    // If no thrust, stop movement
    if (thrustLeft == 0.0 && thrustRight == 0.0) {
      body.clearForces();
      body.linearVelocity = Vector2.zero();
      body.angularVelocity = 0.0;
      positionNotifier.value = body.position.y;
      return;
    }

    // Calculate rotation amount based on thrust difference
    double rotationAmount = 0.0;
    final degreesPerSecond = 1.0;
    if (thrustLeft > 0) {
      rotationAmount += degreesPerSecond * dt * thrustLeft;
    }
    if (thrustRight > 0) {
      rotationAmount -= degreesPerSecond * dt * thrustRight;
    }

    // Calculate upward velocity based on total thrust
    final totalThrust = thrustLeft + thrustRight;
    final upwardVelocity = -1.0 * totalThrust;

    // Apply the rotation and upward velocity
    body.setTransform(body.position, body.angle + rotationAmount);
    body.linearVelocity = Vector2(0.0, upwardVelocity);

    // Limit rotation angle
    if (body.angle < -1.3) {
      body.angularVelocity = 0.0;
      body.setTransform(body.position, -1.3);
    } else if (body.angle > 1.3) {
      body.angularVelocity = 0.0;
      body.setTransform(body.position, 1.3);
    }

    positionNotifier.value = body.position.y;
  }
}
