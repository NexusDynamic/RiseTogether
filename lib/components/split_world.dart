import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:RiseTogether/main.dart';
import 'package:RiseTogether/components/ball.dart';
import 'package:RiseTogether/components/paddle.dart';
import 'package:RiseTogether/components/target.dart';
import 'package:RiseTogether/components/wall.dart';
import 'package:RiseTogether/config.dart';
import 'package:RiseTogether/models/game_state.dart';

/// Main world container for split screen - extends DecoratedWorld to be compatible with WorldRoute
class SplitScreenLevelPage extends DecoratedWorld
    with HasGameRef<RiseTogetherGame>, TapCallbacks, DragCallbacks {
  final String localTeamId;
  final String remoteTeamId;

  late TeamState localTeamState;
  late TeamState remoteTeamState;

  // Local team components
  Ball? localBall;
  Paddle? localPaddle;

  // Remote team components
  Ball? remoteBall;
  Paddle? remotePaddle;

  // UI components
  late TextComponent statusText;
  late TextComponent scoreText;

  SplitScreenLevelPage({required this.localTeamId, required this.remoteTeamId});

  @override
  Future<void> onLoad() async {
    Log.log.fine('SplitScreenLevelPage onLoad started');

    // Initialize camera
    final visibleRect = gameRef.camera.visibleWorldRect;
    // Center the camera properly on the world
    gameRef.camera.viewfinder.position = Vector2(
      visibleRect.center.dx,
      visibleRect.center.dy,
    );

    // Setup UI components in the viewport (not the world)
    statusText = TextComponent(
      text: 'Local: $localTeamId | Remote: $remoteTeamId',
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 16, color: Color(0xFFC8FFF5)),
      ),
      anchor: Anchor.topCenter,
      position: Vector2(gameRef.camera.viewport.size.x / 2, 10),
    );

    scoreText = TextComponent(
      text: 'Local: 0m | Remote: 0m',
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 20, color: Color(0xFFFFFF00)),
      ),
      anchor: Anchor.topCenter,
      position: Vector2(gameRef.camera.viewport.size.x / 2, 30),
    );

    // Add UI components to the viewport
    gameRef.camera.viewport.add(statusText);
    gameRef.camera.viewport.add(scoreText);

    // Create team states
    final ballPosition = Vector2(visibleRect.center.dx, visibleRect.height / 2);

    // Paddle near the bottom but still visible
    final paddlePosition = Vector2(
      visibleRect.center.dx,
      visibleRect.height * 0.8, // 80% down the screen
    );

    localTeamState = TeamState(
      teamId: localTeamId,
      ballPosition: ballPosition,
      paddlePosition: paddlePosition,
    );

    remoteTeamState = TeamState(
      teamId: remoteTeamId,
      ballPosition: ballPosition,
      paddlePosition: paddlePosition,
    );

    // Load asset
    await gameRef.loadSprite('ball.png');

    // Setup local team components (left side)
    await setupLocalTeam();

    // Setup remote team components (right side)
    await setupRemoteTeam();

    // Subscribe to remote team updates via LSL
    if (gameRef.lslService != null) {
      gameRef.lslService!.remoteTeamStateStream.listen((remoteState) {
        updateRemoteTeam(remoteState);
      });
    }

    Log.log.fine('SplitScreenLevelPage onLoad completed');

    return super.onLoad();
  }

  Future<void> setupLocalTeam() async {
    Log.log.fine('Setting up local team');
    final visibleRect = gameRef.camera.visibleWorldRect;
    final worldWidth = visibleRect.width;
    final worldHeight = visibleRect.height;
    final halfScreenWidth = worldWidth / 2;

    // Adjust positions for LEFT side
    final leftCenter = worldWidth / 4; // 1/4 of the way across the screen

    // Ball - centered on the left side
    final ballPos = Vector2(leftCenter, worldHeight / 2);
    Log.log.fine('Local ball position: $ballPos');

    localBall = Ball(
      radius: Config.ballRadius,
      paint: Paint()..color = const Color(0xFFFF0000),
      pos: ballPos,
    );

    // Paddle - place it at 80% down the screen
    final paddleY = worldHeight * 0.8;
    final paddleWidth = 10.0 * Config.ballRadius;
    final paddleHeight = 1.0;

    final paddlePos1 = Vector2(leftCenter - paddleWidth / 2, paddleY);

    final paddlePos2 = Vector2(
      leftCenter + paddleWidth / 2,
      paddleY + paddleHeight,
    );

    Log.log.fine('Local paddle from $paddlePos1 to $paddlePos2');
    localPaddle = Paddle(paddlePos1, paddlePos2);

    // Target - toward the top of the screen
    final targetPos = Vector2(leftCenter, worldHeight * 0.2);
    final target = Target(
      Config.ballRadius * 3,
      targetPos,
      paint: Paint()..color = const Color(0xFF00FF00),
    );

    // Create walls for left side
    final walls = createBoundaries(true, halfScreenWidth);

    // Add all local components
    add(localBall!);
    add(localPaddle!);
    add(target);

    for (final wall in walls) {
      add(wall);
    }
  }

  Future<void> setupRemoteTeam() async {
    Log.log.fine('Setting up remote team');
    final visibleRect = gameRef.camera.visibleWorldRect;
    final worldWidth = visibleRect.width;
    final worldHeight = visibleRect.height;
    final halfScreenWidth = worldWidth / 2;

    // Adjust positions for RIGHT side
    final rightCenter = 3 * worldWidth / 4; // 3/4 of the way across the screen

    // Ball - centered on the right side
    final ballPos = Vector2(rightCenter, worldHeight / 2);
    Log.log.fine('Remote ball position: $ballPos');

    remoteBall = Ball(
      radius: Config.ballRadius,
      paint: Paint()..color = const Color(0xFF0000FF),
      pos: ballPos,
    );

    // Paddle - place it at 80% down the screen
    final paddleY = worldHeight * 0.8;
    final paddleWidth = 10.0 * Config.ballRadius;
    final paddleHeight = 1.0;

    final paddlePos1 = Vector2(rightCenter - paddleWidth / 2, paddleY);

    final paddlePos2 = Vector2(
      rightCenter + paddleWidth / 2,
      paddleY + paddleHeight,
    );

    Log.log.fine('Remote paddle from $paddlePos1 to $paddlePos2');
    remotePaddle = Paddle(paddlePos1, paddlePos2);

    // Target - toward the top of the screen
    final targetPos = Vector2(rightCenter, worldHeight * 0.2);
    final target = Target(
      Config.ballRadius * 3,
      targetPos,
      paint: Paint()..color = const Color(0xFFFF9900),
    );

    // Create walls for right side
    final walls = createBoundaries(false, halfScreenWidth);

    // Add all remote components
    add(remoteBall!);
    add(remotePaddle!);
    add(target);

    for (final wall in walls) {
      add(wall);
    }
  }

  List<Component> createBoundaries(bool isLocalTeam, double halfScreenWidth) {
    final visibleRect = gameRef.camera.visibleWorldRect;
    final height = visibleRect.height;
    final width = halfScreenWidth;

    // Calculate the starting X position
    final double startX = isLocalTeam ? 0 : halfScreenWidth;
    final double endX = startX + width;

    // Create boundary points using full height
    final topLeft = Vector2(startX, 0);
    final topRight = Vector2(endX, 0);
    final bottomRight = Vector2(endX, height);
    final bottomLeft = Vector2(startX, height);

    // Use different colors for local and remote teams
    final paint =
        Paint()
          ..color =
              isLocalTeam
                  ? const Color.fromARGB(255, 255, 0, 0) // Red for local
                  : const Color.fromARGB(255, 0, 0, 255); // Blue for remote

    Log.log.fine(
      '${isLocalTeam ? "Local" : "Remote"} boundaries: TL:$topLeft, TR:$topRight, BR:$bottomRight, BL:$bottomLeft',
    );

    return [
      Wall(topLeft, topRight, paint: paint),
      Wall(topRight, bottomRight, paint: paint),
      Wall(bottomRight, bottomLeft, paint: paint),
      Wall(bottomLeft, topLeft, paint: paint),
    ];
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (localPaddle == null) return;

    try {
      // Get tap position in world coordinates
      final tapPos = gameRef.screenToWorld(event.canvasPosition);
      final worldWidth = gameRef.camera.visibleWorldRect.width;

      Log.log.fine('Tap position: $tapPos, worldWidth: $worldWidth');

      // Check if we're on the left half of the screen
      if (tapPos.x < worldWidth / 2) {
        final leftQuarter = worldWidth / 4;

        // Determine if left or right side of the paddle
        if (tapPos.x < leftQuarter) {
          Log.log.fine('Pressing local paddle LEFT');
          localPaddle!.pressLeft();
          localTeamState.playerInputs[gameRef.participantId] = "left";
          gameRef.lslService?.sendPlayerInput("left");
        } else {
          Log.log.fine('Pressing local paddle RIGHT');
          localPaddle!.pressRight();
          localTeamState.playerInputs[gameRef.participantId] = "right";
          gameRef.lslService?.sendPlayerInput("right");
        }
      }
    } catch (e) {
      Log.log.warning('Error in onTapDown: $e');
    }
  }

  void updateRemoteTeam(TeamState newState) {
    // Update our stored state
    remoteTeamState = newState;

    // Only update remote components if fully initialized
    if (remotePaddle != null && remoteBall != null) {
      try {
        // Adjust positions for split screen
        final worldWidth = gameRef.camera.visibleWorldRect.width;
        final rightCenter = 3 * worldWidth / 4;

        // Calculate offset from center to maintain relative positioning
        final offsetX = rightCenter - newState.ballPosition.x;

        // Update ball position
        final adjustedBallPos = Vector2(rightCenter, newState.ballPosition.y);
        remoteBall!.body.setTransform(adjustedBallPos, remoteBall!.body.angle);

        // Update paddle angle
        remotePaddle!.body.setTransform(
          remotePaddle!.body.position,
          newState.paddleAngle,
        );
      } catch (e) {
        Log.log.warning('Error updating remote team: $e');
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Update local team state
    try {
      if (localBall != null && localPaddle != null) {
        localTeamState.ballPosition = localBall!.position;
        localTeamState.paddleAngle = localPaddle!.body.angle;

        // Increment distance (this would be your actual game logic)
        localTeamState.distance += dt * 2;

        // Send local team state updates through LSL
        gameRef.lslService?.sendTeamState(localTeamState);
      }

      // Update score display
      final localDistance = localTeamState.distance.toStringAsFixed(1);
      final remoteDistance = remoteTeamState.distance.toStringAsFixed(1);
      scoreText.text = 'Local: ${localDistance}m | Remote: ${remoteDistance}m';
    } catch (e) {
      Log.log.warning('Error in update: $e');
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (localPaddle == null) return;

    try {
      // Release both sides of paddle on tap up
      localPaddle!.releaseLeft();
      localPaddle!.releaseRight();
      localTeamState.playerInputs[gameRef.participantId] = "none";
      gameRef.lslService?.sendPlayerInput("none");
    } catch (e) {
      Log.log.warning('Error in onTapUp: $e');
    }
  }
}
