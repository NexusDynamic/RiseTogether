import 'package:flame_forge2d/flame_forge2d.dart';

abstract mixin class PositionableBodyComponent {
  abstract Body body;
  bool _pendingPositionUpdate = false;
  bool _pendingAngleUpdate = false;
  final Vector2 _pendingPosition = Vector2.zero();
  double _pendingAngle = 0.0;
  bool get hasPendingPositionUpdate => _pendingPositionUpdate;
  bool get hasPendingAngleUpdate => _pendingAngleUpdate;
  bool get hasPendingTransforms =>
      _pendingPositionUpdate || _pendingAngleUpdate;

  /// Sets the position of the object.
  void setPosition(Vector2 position) {
    _pendingPositionUpdate = true;
    _pendingPosition.setFrom(position);
  }

  /// Sets the angle of the object.
  void setAngle(double angle) {
    _pendingAngleUpdate = true;
    _pendingAngle = angle;
  }

  void stopMovement() {
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0.0;
  }

  void cancelPendingPositionUpdate() {
    _pendingPositionUpdate = false;
  }

  void cancelPendingAngleUpdate() {
    _pendingAngleUpdate = false;
  }

  void cancelPendingTransforms() {
    cancelPendingPositionUpdate();
    cancelPendingAngleUpdate();
  }

  /// Updates the position and angle of the object if a pending update is set.
  void applyPendingTransforms() {
    if (!_pendingPositionUpdate && !_pendingAngleUpdate) {
      return;
    }
    body.setTransform(
      _pendingPositionUpdate ? _pendingPosition : body.position,
      _pendingAngleUpdate ? _pendingAngle : body.angle,
    );
    _pendingAngleUpdate = false;
    _pendingPositionUpdate = false;
  }
}
