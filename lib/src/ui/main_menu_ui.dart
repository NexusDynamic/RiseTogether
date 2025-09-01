import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/game/tournament_manager.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/network_coordinator.dart';

class MainMenuUI extends StatelessWidget
    with AppLogging
    implements RiseTogetherOverlay {
  static final String overlayID = 'MainMenu';
  final RiseTogetherGame game;
  final NetworkCoordinator networkCoordinator;
  final Future<void> Function() onStartGame;

  MainMenuUI(this.game, this.networkCoordinator, this.onStartGame, {super.key});

  @override
  Widget build(BuildContext context) {
    appLog.info('Building MainMenu overlay');
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth,
      height: screenHeight,
      color: Color.fromARGB(200, 0, 0, 0), // Semi-transparent background
      child: Stack(
        children: [
          // Game title
          Positioned(
            top: screenHeight * 0.2,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  'Rise Together',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color.fromARGB(255, 255, 255, 255),
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                // Tournament Score Display
                ChangeNotifierProvider.value(
                  value: game.tournamentManager,
                  builder: (ctx, _) {
                    final tournamentManager = Provider.of<TournamentManager>(
                      ctx,
                    );
                    return Text(
                      'Tournament Score - Team 1: ${tournamentManager.team1RoundWins} | Team 2: ${tournamentManager.team2RoundWins}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color.fromARGB(200, 255, 255, 255),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        backgroundColor: Color.fromARGB(100, 0, 0, 0),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Start game button (coordinator only) or waiting status
          Positioned(
            top: screenHeight * 0.45,
            left: screenWidth * 0.25,
            right: screenWidth * 0.25,
            child: ChangeNotifierProvider.value(
              value: networkCoordinator,
              child: Consumer<NetworkCoordinator>(
                builder: (context, coordinator, child) {
                  if (coordinator.isCoordinator) {
                    if (coordinator.gameStarting) {
                      return _buildCoordinatorWaitingWidget(context, coordinator);
                    } else {
                      return _buildStartButton(context);
                    }
                  } else {
                    return _buildWaitingForCoordinatorWidget(context);
                  }
                },
              ),
            ),
          ),

          // Reset game button
          Positioned(
            top: screenHeight * 0.55,
            left: screenWidth * 0.25,
            right: screenWidth * 0.25,
            child: _buildResetButton(context),
          ),
          
          // Coordination button (if coordinator) - reactive to role changes
          ChangeNotifierProvider.value(
            value: networkCoordinator,
            child: Consumer<NetworkCoordinator>(
              builder: (context, coordinator, child) {
                return coordinator.isCoordinator
                  ? Positioned(
                      top: screenHeight * 0.65,
                      left: screenWidth * 0.25,
                      right: screenWidth * 0.25,
                      child: _buildCoordinationButton(context),
                    )
                  : SizedBox.shrink();
              },
            ),
          ),
          
          // Network status in top left
          Positioned(
            top: 40,
            left: 40,
            child: _buildNetworkStatus(context),
          ),
          
          // Settings icon in top right corner
          Positioned(top: 40, right: 40, child: _buildSettingsButton(context)),
        ],
      ),
    );
  }

  Widget _buildStartButton(BuildContext context) {
    return GestureDetector(
      onTap: _startGame,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 0, 150, 255),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB(100, 0, 0, 0),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Start Game',
            style: TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinatorWaitingWidget(BuildContext context, NetworkCoordinator coordinator) {
    String statusText;
    Color backgroundColor;
    Color textColor;
    
    if (coordinator.scheduledStartTime != null) {
      final remainingSeconds = coordinator.scheduledStartTime!
          .difference(DateTime.now())
          .inSeconds;
      if (remainingSeconds > 0) {
        statusText = 'Game Starting in ${remainingSeconds}s';
        backgroundColor = Color.fromARGB(255, 255, 165, 0);
        textColor = Color.fromARGB(255, 255, 255, 255);
      } else {
        statusText = 'Game Starting Now!';
        backgroundColor = Color.fromARGB(255, 0, 255, 0);
        textColor = Color.fromARGB(255, 0, 0, 0);
      }
    } else {
      final readyCount = coordinator.readyNodes.length;
      final totalCount = coordinator.connectedNodes.length;
      statusText = 'Waiting for Players $readyCount/$totalCount Ready';
      backgroundColor = Color.fromARGB(255, 0, 150, 255);
      textColor = Color.fromARGB(255, 255, 255, 255);
    }

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Color.fromARGB(100, 255, 255, 255),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          statusText,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingForCoordinatorWidget(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: networkCoordinator,
      child: Consumer<NetworkCoordinator>(
        builder: (context, coordinator, child) {
          String statusText;
          Color backgroundColor;
          Color textColor;
          
          if (coordinator.gameStarting) {
            if (coordinator.scheduledStartTime != null) {
              final remainingSeconds = coordinator.scheduledStartTime!
                  .difference(DateTime.now())
                  .inSeconds;
              if (remainingSeconds > 0) {
                statusText = 'Game Starting in ${remainingSeconds}s';
                backgroundColor = Color.fromARGB(255, 255, 165, 0);
                textColor = Color.fromARGB(255, 255, 255, 255);
              } else {
                statusText = 'Game Starting Now!';
                backgroundColor = Color.fromARGB(255, 0, 255, 0);
                textColor = Color.fromARGB(255, 0, 0, 0);
              }
            } else {
              statusText = 'Waiting for All Players Ready...';
              backgroundColor = Color.fromARGB(255, 255, 165, 0);
              textColor = Color.fromARGB(255, 255, 255, 255);
            }
          } else if (coordinator.gameActive) {
            statusText = 'Game in Progress';
            backgroundColor = Color.fromARGB(255, 0, 255, 0);
            textColor = Color.fromARGB(255, 0, 0, 0);
          } else {
            statusText = 'Waiting for Coordinator to Start';
            backgroundColor = Color.fromARGB(255, 100, 100, 100);
            textColor = Color.fromARGB(200, 255, 255, 255);
          }

          return Container(
            height: 60,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Color.fromARGB(100, 255, 255, 255),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                statusText,
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResetButton(BuildContext context) {
    return GestureDetector(
      onTap: _resetGame,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 255, 100, 0),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB(100, 0, 0, 0),
              spreadRadius: 2,
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Reset Game',
            style: TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinationButton(BuildContext context) {
    return GestureDetector(
      onTap: _openCoordination,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 150, 0, 255),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB(100, 0, 0, 0),
              spreadRadius: 2,
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Coordination',
            style: TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkStatus(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: networkCoordinator,
      child: Consumer<NetworkCoordinator>(
        builder: (context, coordinator, child) {
          return Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color.fromARGB(180, 0, 0, 0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Network Status',
                  style: TextStyle(
                    color: Color.fromARGB(255, 255, 255, 255),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  coordinator.isInitialized 
                    ? (coordinator.isCoordinator ? 'Coordinator' : 'Participant')
                    : 'Connecting...',
                  style: TextStyle(
                    color: coordinator.isInitialized 
                      ? Color.fromARGB(255, 0, 255, 0)
                      : Color.fromARGB(255, 255, 255, 0),
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Nodes: ${coordinator.connectedNodes.length}',
                  style: TextStyle(
                    color: Color.fromARGB(200, 255, 255, 255),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return GestureDetector(
      onTap: _openSettings,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Color.fromARGB(180, 100, 100, 100),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB(100, 0, 0, 0),
              spreadRadius: 2,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.settings,
          color: Color.fromARGB(255, 255, 255, 255),
          size: 25,
        ),
      ),
    );
  }


  void _startGame() async {
    appLog.info('Starting game - configuring and starting with new architecture');
    
    try {
      // Use the new lifecycle: configure and start game
      await onStartGame();
      
      // Don't transition UI here - wait for coordinated start callback
      // UI transition will happen in _onGameActuallyStarted callback
      
      appLog.info('Game coordination started - waiting for synchronized start');
    } catch (e) {
      appLog.severe('Failed to start game: $e');
      // Could show error dialog here
    }
  }

  void _openCoordination() {
    appLog.info('Opening coordination overlay');
    
    // Add the coordination overlay
    game.overlays.add('Coordination');
  }

  void _openSettings() {
    appLog.info('Opening settings overlay');

    // Add the settings overlay
    game.overlays.add('Settings');
  }

  void _resetGame() {
    appLog.info('Resetting game from main menu');

    // Reset the game state
    game.resetGame();
  }
}
