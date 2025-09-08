import 'dart:async';
import 'package:flame/components.dart';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/game/rise_together_world.dart';
import 'package:rise_together/src/components/paddle.dart';
import 'package:rise_together/src/models/team_thrust.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Controls the connection between team action streams and world paddles
class WorldController with AppLogging {
  final RiseTogetherWorld world;
  TeamActionStream actionStream;
  late StreamSubscription<TeamThrust> _thrustSubscription;
  Paddle? _paddle;
  final bool shouldUpdateParallax;
  final int configuredTeamPlayerCount;

  WorldController({
    required this.world, 
    required this.actionStream,
    this.shouldUpdateParallax = true,
    required this.configuredTeamPlayerCount,
  });

  void initialize() {
    appLog.fine('Initializing WorldController for team ${actionStream.teamId}');

    _thrustSubscription = actionStream.thrustStream.listen((thrust) {
      _updatePaddleThrust(thrust);
    });
  }

  void setActionStream(TeamActionStream newStream) {
    // Cancel existing subscription
    _thrustSubscription.cancel();

    actionStream = newStream;

    // Resubscribe to the new stream
    _thrustSubscription = actionStream.thrustStream.listen((thrust) {
      _updatePaddleThrust(thrust);
    });

    appLog.fine('Action stream updated for team ${actionStream.teamId}');
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
    final totalThrust = _paddle!.setThrust(
      thrust.leftThrust,
      thrust.rightThrust,
    );
    
    // Only update parallax if this controller should handle it (coordinator only)
    if (shouldUpdateParallax) {
      // Use the corrected thrust values from TeamActionStream (which now uses configured team size)
      world.parallax.parallax!.baseVelocity.setFrom(Vector2(0, -totalThrust));
      print('WorldController team ${actionStream.teamId}: totalThrust=$totalThrust (from TeamActionStream)');
    }
    appLog.finest('Updated paddle thrust: ${thrust.toString()}');
  }

  Paddle get paddle {
    if (_paddle == null) {
      appLog.warning('Paddle is not set for team ${actionStream.teamId}');
      throw StateError('Paddle is not set');
    }
    return _paddle!;
  }

  double levelProgress(double position) {
    // Calculate progress based on paddle position
    final progress = position.abs() / world.level.verticalMultiplier;
    return progress.clamp(0.0, 1.0);
  }

  void dispose() {
    _thrustSubscription.cancel();
    appLog.fine('WorldController disposed for team ${actionStream.teamId}');
  }
}
