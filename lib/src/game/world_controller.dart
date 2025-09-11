import 'dart:async';
import 'package:flame/components.dart';
import 'package:rise_together/src/attributes/resetable.dart';
import 'package:rise_together/src/game/action_system.dart';
import 'package:rise_together/src/game/rise_together_world.dart';
import 'package:rise_together/src/components/paddle.dart';
import 'package:rise_together/src/models/team_thrust.dart';
import 'package:rise_together/src/models/team_context.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Controls the connection between team action streams and world paddles
class WorldController with AppLogging, Resetable {
  final RiseTogetherWorld world;
  TeamActionStream get actionStream => _teamContext.actionStream;
  late StreamSubscription<TeamThrust> _thrustSubscription;
  bool shouldUpdateParallax;
  int configuredTeamPlayerCount;

  /// Team context providing consolidated team information
  TeamContext _teamContext;
  TeamContext get team => _teamContext;

  WorldController({
    required this.world,
    this.shouldUpdateParallax = true,
    required this.configuredTeamPlayerCount,
    required TeamContext teamContext,
  }) : _teamContext = teamContext {
    // Vital
    world.setWorldController(this);
    _thrustSubscription = actionStream.thrustStream.listen((thrust) {
      _updatePaddleThrust(thrust);
    });
  }

  // void initialize() {
  //   appLog.fine('Initializing WorldController for team ${actionStream.teamId}');
  // }

  // void setActionStream(TeamActionStream newStream) {
  //   // Cancel existing subscription
  //   _thrustSubscription.cancel();

  //   actionStream = newStream;

  //   // Resubscribe to the new stream
  //   _thrustSubscription = actionStream.thrustStream.listen((thrust) {
  //     _updatePaddleThrust(thrust);
  //   });

  //   appLog.fine('Action stream updated for team ${actionStream.teamId}');
  // }

  /// Update the team context and notify the world
  void setTeamContext(TeamContext teamContext) {
    _thrustSubscription.cancel();
    _teamContext = teamContext;
    world.updateTeamContext(teamContext);
    _thrustSubscription = actionStream.thrustStream.listen((thrust) {
      _updatePaddleThrust(thrust);
    });
    // TODO: Fix hack...
    configuredTeamPlayerCount = _teamContext.players.length;
    actionStream.setConfiguredTeamPlayerCount(configuredTeamPlayerCount);
    appLog.fine('Team context updated: ${teamContext.toString()}');
  }

  /// Get current team context
  TeamContext get teamContext => _teamContext;

  void _updatePaddleThrust(TeamThrust thrust) {
    // Update paddle with new thrust values
    final totalThrust = world.paddle.setThrust(
      thrust.leftThrust,
      thrust.rightThrust,
    );

    // Only update parallax if this controller should handle it (coordinator only)
    if (shouldUpdateParallax) {
      // Use the corrected thrust values from TeamActionStream (which now uses configured team size)
      world.parallax.parallax!.baseVelocity.setFrom(Vector2(0, -totalThrust));
    }
    appLog.finest('Updated paddle thrust: ${thrust.toString()}');
  }

  void stopMovement() {
    world.ball.body.linearVelocity = Vector2.zero();
    world.ball.body.angularVelocity = 0.0;
    world.paddle.body.linearVelocity = Vector2.zero();
    world.paddle.body.angularVelocity = 0.0;
  }

  Paddle get paddle => world.paddle;

  double levelProgress(double position) {
    // Calculate progress based on paddle position
    final progress = position.abs() / world.level.verticalMultiplier;
    return progress.clamp(0.0, 1.0);
  }

  @override
  void reset() {
    world.reset();
    actionStream.clearAllActions();

    // Update distance tracker with ball's start position
    world.game.distanceTracker.setStartingHeight(
      _teamContext.teamId,
      world.ball.startPosition.y,
    );

    appLog.fine('WorldController reset for team ${actionStream.teamId}');
  }

  void updatePaddleWidth(double widthMultiplier) {
    world.paddle.updatePaddleShape(
      world.paddleStart(widthMultiplier),
      world.paddleEnd(widthMultiplier),
    );
  }

  void dispose() {
    _thrustSubscription.cancel();
    appLog.fine('WorldController disposed for team ${actionStream.teamId}');
  }
}
