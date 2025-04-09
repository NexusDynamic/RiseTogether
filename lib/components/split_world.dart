import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show BodyComponent;
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
  List<BodyComponent<RiseTogetherGame>> localWorldElements = [];

  // Remote team components
  Ball? remoteBall;
  Paddle? remotePaddle;
  List<BodyComponent<RiseTogetherGame>> remoteWorldElements = [];

  // Camera and viewport variables
  late double worldWidth;
  late double worldHeight;
  late double halfScreenWidth;
  double worldOffset = 0; // How far the world has "moved down"

  // UI components
  late TextComponent statusText;
  late TextComponent scoreText;
  late TextComponent debugText;

  SplitScreenLevelPage({required this.localTeamId, required this.remoteTeamId});

  @override
  Future<void> onLoad() async {
    Log.log.fine('SplitScreenLevelPage onLoad started');

    // Force reset camera position to origin before getting dimensions
    gameRef.camera.viewfinder.position = Vector2.zero();

    // Get the visible world rectangle AFTER resetting camera
    final visibleRect = gameRef.camera.visibleWorldRect;
    worldWidth = visibleRect.width;
    worldHeight = visibleRect.height;
    halfScreenWidth = worldWidth / 2;

    Log.log.fine('Visible world: width=$worldWidth, height=$worldHeight');

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

    debugText = TextComponent(
      text: 'Debug: Initializing...',
      textRenderer: TextPaint(
        style: const TextStyle(fontSize: 14, color: Color(0xFFFF00FF)),
      ),
      anchor: Anchor.topLeft,
      position: Vector2(10, 50),
    );

    // Add UI components to the viewport
    gameRef.camera.viewport.add(statusText);
    gameRef.camera.viewport.add(scoreText);
    gameRef.camera.viewport.add(debugText);

    // Set initial ball and paddle positions
    final ballPositionY = worldHeight * 0.6; // Lower to ensure visibility
    final paddlePositionY =
        ballPositionY + Config.ballRadius * 3; // Below the ball

    // Create team states
    localTeamState = TeamState(
      teamId: localTeamId,
      ballPosition: Vector2(worldWidth * 0.25, ballPositionY), // 1/4 across
      paddlePosition: Vector2(worldWidth * 0.25, paddlePositionY),
    );

    remoteTeamState = TeamState(
      teamId: remoteTeamId,
      ballPosition: Vector2(worldWidth * 0.75, ballPositionY), // 3/4 across
      paddlePosition: Vector2(worldWidth * 0.75, paddlePositionY),
    );

    // Load asset
    await gameRef.loadSprite('ball.png');

    // First add walls to ensure they're behind other elements
    final localWalls = createBoundaries(true);
    final remoteWalls = createBoundaries(false);

    for (final wall in localWalls) {
      add(wall);
      localWorldElements.add(wall);
    }

    for (final wall in remoteWalls) {
      add(wall);
      remoteWorldElements.add(wall);
    }

    // Setup local team components (left side)
    await setupLocalTeam();

    // Setup remote team components (right side)
    await setupRemoteTeam();

    // Subscribe to remote team updates via LSL
    if (gameRef.lslService != null) {
      gameRef.lslService!.remoteTeamStateStream.listen((remoteState) {
        updateRemoteTeam(remoteState);
      });
      gameRef.lslService!.remotePlayerInputStream.listen((input) {
        // Handle remote player input if needed
        Log.log.fine('Remote player input: $input');
        updateRemoteTeamByInput(input);
      });
    }

    debugText.text =
        'Debug: Setup complete. L paddle: ${localPaddle?.position}, R paddle: ${remotePaddle?.position}';
    Log.log.fine('SplitScreenLevelPage onLoad completed');

    return super.onLoad();
  }

  Future<void> setupLocalTeam() async {
    Log.log.fine('Setting up local team');
    final leftCenter = worldWidth * 0.25; // 1/4 of the way across

    // Ball - centered on the left side horizontally
    final ballPos = Vector2(leftCenter, localTeamState.ballPosition.y);
    Log.log.fine('Local ball position: $ballPos');

    localBall = Ball(
      radius: Config.ballRadius,
      paint: Paint()..color = const Color(0xFFFF0000),
      pos: ballPos,
    );

    // Paddle - place it below the ball
    final paddleY = localTeamState.paddlePosition.y;
    final paddleWidth = 10.0 * Config.ballRadius;
    final paddleHeight = 1.0;

    final paddlePos1 = Vector2(leftCenter - paddleWidth / 2, paddleY);
    final paddlePos2 = Vector2(
      leftCenter + paddleWidth / 2,
      paddleY + paddleHeight,
    );

    Log.log.fine('Local paddle from $paddlePos1 to $paddlePos2');
    localPaddle = Paddle(paddlePos1, paddlePos2);

    // Target - above the paddle
    final targetPos = Vector2(leftCenter, worldHeight * 0.2);
    final target = Target(
      Config.ballRadius * 3,
      targetPos,
      paint: Paint()..color = const Color(0xFF00FF00),
    );
    localWorldElements.add(target);
    add(target);

    // Add ball and paddle to the world
    add(localBall!);
    add(localPaddle!);

    // Paddle isn't initialized yet
    // Log.log.fine(
    //   'Local team setup complete. Paddle at ${localPaddle!.position}',
    // );
    debugText.text = 'Local paddle added at: ${paddlePos1} to ${paddlePos2}';
  }

  Future<void> setupRemoteTeam() async {
    Log.log.fine('Setting up remote team');
    final rightCenter = worldWidth * 0.75; // 3/4 of the way across

    // Ball - centered on the right side horizontally
    final ballPos = Vector2(rightCenter, remoteTeamState.ballPosition.y);
    Log.log.fine('Remote ball position: $ballPos');

    remoteBall = Ball(
      radius: Config.ballRadius,
      paint: Paint()..color = const Color(0xFF0000FF),
      pos: ballPos,
    );

    // Paddle - place it below the ball
    final paddleY = remoteTeamState.paddlePosition.y;
    final paddleWidth = 10.0 * Config.ballRadius;
    final paddleHeight = 1.0;

    final paddlePos1 = Vector2(rightCenter - paddleWidth / 2, paddleY);
    final paddlePos2 = Vector2(
      rightCenter + paddleWidth / 2,
      paddleY + paddleHeight,
    );

    Log.log.fine('Remote paddle from $paddlePos1 to $paddlePos2');
    remotePaddle = Paddle(paddlePos1, paddlePos2);

    // Target - above the paddle
    final targetPos = Vector2(rightCenter, worldHeight * 0.2);
    final target = Target(
      Config.ballRadius * 3,
      targetPos,
      paint: Paint()..color = const Color(0xFFFF9900),
    );
    remoteWorldElements.add(target);
    add(target);

    // Add ball and paddle to the world
    add(remoteBall!);
    add(remotePaddle!);

    // Paddle isn't initialized yet
    // Log.log.fine(
    //   'Remote team setup complete. Paddle at ${remotePaddle!.position}',
    // );
  }

  List<BodyComponent<RiseTogetherGame>> createBoundaries(bool isLocalTeam) {
    final height = worldHeight;
    final width = worldWidth / 2;

    // Calculate the starting X position based on team
    final double startX = isLocalTeam ? 0 : width;
    final double endX = startX + width;

    // Create boundary points
    final topLeft = Vector2(startX, 0); // Top of screen
    final topRight = Vector2(endX, 0);
    final bottomRight = Vector2(endX, height); // Bottom of screen
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
      Wall(topLeft, topRight, paint: paint), // Top wall
      Wall(topRight, bottomRight, paint: paint), // Right wall
      Wall(bottomRight, bottomLeft, paint: paint), // Bottom wall
      Wall(bottomLeft, topLeft, paint: paint), // Left wall
    ];
  }

  void handleRemoteTap(String input) {
    // Handle remote tap input
    if (input == "left") {
      remotePaddle!.pressLeft();
      remoteTeamState.playerInputs[gameRef.participantId] = "left";
    } else if (input == "right") {
      remotePaddle!.pressRight();
      remoteTeamState.playerInputs[gameRef.participantId] = "right";
    } else {
      remotePaddle!.releaseLeft();
      remotePaddle!.releaseRight();
      remoteTeamState.playerInputs[gameRef.participantId] = "none";
    }
  }

  void handleTap(Vector2 tapPos) {
    debugText.text = 'Tap at: $tapPos';

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
        debugText.text = 'Left paddle LEFT pressed';
      } else {
        Log.log.fine('Pressing local paddle RIGHT');
        localPaddle!.pressRight();
        localTeamState.playerInputs[gameRef.participantId] = "right";
        gameRef.lslService?.sendPlayerInput("right");
        debugText.text = 'Left paddle RIGHT pressed';
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (localPaddle == null) return;

    try {
      // Get tap position in world coordinates
      final tapPos = gameRef.screenToWorld(event.canvasPosition);
      handleTap(tapPos);
    } catch (e) {
      Log.log.warning('Error in onTapDown: $e');
      debugText.text = 'Error: $e';
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (localPaddle == null) return;

    try {
      // Get drag position in world coordinates
      final dragPos = gameRef.screenToWorld(event.canvasPosition);
      handleTap(dragPos);
    } catch (e) {
      Log.log.warning('Error in onDragStart: $e');
      debugText.text = 'Error: $e';
    }
  }

  void updateRemoteTeamByInput(String input) {
    // Update remote team state based on input
    if (input == "left") {
      remotePaddle!.pressLeft();
    } else if (input == "right") {
      remotePaddle!.pressRight();
    } else {
      remotePaddle!.releaseLeft();
      remotePaddle!.releaseRight();
    }
  }

  void updateRemoteTeam(TeamState newState) {
    // Update our stored state
    remoteTeamState = newState;

    // Only update remote components if fully initialized
    if (remotePaddle != null && remoteBall != null) {
      try {
        // Update paddle angle
        remotePaddle!.body.setTransform(
          remotePaddle!.body.position,
          newState.paddleAngle,
        );

        // Update world elements based on remote team's distance
        updateRemoteWorldElements(newState.distance);
      } catch (e) {
        Log.log.warning('Error updating remote team: $e');
      }
    }
  }

  void updateLocalWorldElements(double distanceIncrement) {
    for (final element in localWorldElements) {
      if (element is Target) {
        // Move target down based on distance
        element.body.setTransform(
          Vector2(
            element.body.position.x,
            element.body.position.y + distanceIncrement,
          ),
          element.body.angle,
        );
      }
      // Note: We don't move walls to maintain the play area
    }
  }

  void updateRemoteWorldElements(double remoteDistance) {
    for (final element in remoteWorldElements) {
      if (element is Target) {
        // Move target down based on remote team's distance
        element.body.setTransform(
          Vector2(
            element.body.position.x,
            element.body.position.y + remoteDistance,
          ),
          element.body.angle,
        );
      }
      // Note: We don't move walls to maintain the play area
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Update local team state
    try {
      if (localBall != null && localPaddle != null) {
        // Update ball and paddle positions in the state
        localTeamState.ballPosition = localBall!.position;
        localTeamState.paddleAngle = localPaddle!.body.angle;

        // Debug paddle positions
        debugText.text =
            'L paddle: ${localPaddle!.position.y.toStringAsFixed(1)}, '
            'R paddle: ${remotePaddle?.position.y.toStringAsFixed(1) ?? "N/A"}';

        // Calculate the distance traveled based on paddle's lift (ball's Y velocity)
        double yVelocity = localBall!.body.linearVelocity.y;

        // If the ball is rising (negative Y velocity in Forge2D), increase distance
        if (yVelocity < 0) {
          // Convert velocity to distance increment
          double distanceIncrement =
              -yVelocity * dt * 0.1; // Scale factor for visibility
          localTeamState.distance += distanceIncrement;

          // Move world elements down to simulate rising
          updateLocalWorldElements(distanceIncrement);
        }

        // Send local team state updates through LSL
        gameRef.lslService?.sendTeamState(localTeamState);
      }

      // Update score display
      final localDistance = localTeamState.distance.toStringAsFixed(1);
      final remoteDistance = remoteTeamState.distance.toStringAsFixed(1);
      scoreText.text = 'Local: ${localDistance}m | Remote: ${remoteDistance}m';
    } catch (e) {
      Log.log.warning('Error in update: $e');
      debugText.text = 'Update error: $e';
    }
  }

  void handleTapUp() {
    // Release both sides of paddle on tap up
    localPaddle!.releaseLeft();
    localPaddle!.releaseRight();
    localTeamState.playerInputs[gameRef.participantId] = "none";
    gameRef.lslService?.sendPlayerInput("none");
    debugText.text = 'Paddle released';
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (localPaddle == null) return;

    try {
      handleTapUp();
    } catch (e) {
      Log.log.warning('Error in onTapUp: $e');
      debugText.text = 'Release error: $e';
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (localPaddle == null) return;

    try {
      handleTapUp();
    } catch (e) {
      Log.log.warning('Error in onDragEnd: $e');
      debugText.text = 'Release error: $e';
    }
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (localPaddle == null) return;

    try {
      handleTapUp();
    } catch (e) {
      Log.log.warning('Error in onDragCancel: $e');
      debugText.text = 'Release error: $e';
    }
  }
}
