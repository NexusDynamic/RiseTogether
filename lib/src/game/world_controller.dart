import 'dart:async';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/game/rise_together_world.dart';
import 'package:rise_together/src/components/paddle.dart';
import 'package:rise_together/src/models/team_thrust.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Controls the connection between team action streams and world paddles
class WorldController with AppLogging {
  final RiseTogetherWorld world;
  final TeamActionStream actionStream;
  late StreamSubscription<TeamThrust> _thrustSubscription;
  Paddle? _paddle;

  WorldController({required this.world, required this.actionStream});

  void initialize() {
    appLog.fine('Initializing WorldController for team ${actionStream.teamId}');

    _thrustSubscription = actionStream.thrustStream.listen((thrust) {
      _updatePaddleThrust(thrust);
    });
  }

  void setPaddle(Paddle paddle) {
    _paddle = paddle;
    appLog.fine('Paddle set for team ${actionStream.teamId}');
  }

  void _updatePaddleThrust(TeamThrust thrust) {
    if (_paddle == null) {
      appLog.warning('Attempted to update paddle thrust but paddle is null');
      return;
    }

    // Update paddle with new thrust values
    _paddle!.setThrust(thrust.leftThrust, thrust.rightThrust);

    appLog.finest('Updated paddle thrust: ${thrust.toString()}');
  }

  void dispose() {
    _thrustSubscription.cancel();
    appLog.fine('WorldController disposed for team ${actionStream.teamId}');
  }
}
