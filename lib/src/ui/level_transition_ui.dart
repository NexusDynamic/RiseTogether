import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/game/tournament_manager.dart';
import 'package:rise_together/src/game/distance_tracker.dart';
import 'package:rise_together/src/attributes/resetable.dart';
import 'package:rise_together/src/services/log_service.dart';

class LevelTransitionUI extends StatelessWidget
    with AppLogging
    implements RiseTogetherOverlay {
  static final String overlayID = 'LevelTransition';
  final RiseTogetherGame game;

  LevelTransitionUI(this.game, {super.key});

  @override
  Widget build(BuildContext context) {
    appLog.info('Building LevelTransition overlay');
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth,
      height: screenHeight,
      color: Color.fromARGB(220, 0, 0, 0), // Semi-transparent background
      child: Center(
        child: Container(
          width: screenWidth * 0.8,
          height: screenHeight * 0.7,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, 40, 40, 40),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Color.fromARGB(150, 0, 0, 0),
                spreadRadius: 4,
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildHeader(context),
                  SizedBox(height: 30),
                  _buildLevelResults(context),
                  SizedBox(height: 30),
                  _buildTournamentProgress(context),
                  SizedBox(height: 40),
                  _buildReadyButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: game.tournamentManager,
      builder: (ctx, _) {
        final tournamentManager = Provider.of<TournamentManager>(ctx);
        final isComplete = tournamentManager.isTournamentComplete;

        return Column(
          children: [
            Text(
              isComplete ? 'Tournament Complete!' : 'Level Complete!',
              style: TextStyle(
                color: Color.fromARGB(255, 255, 255, 255),
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!isComplete) ...[
              SizedBox(height: 10),
              Text(
                tournamentManager.levelProgress,
                style: TextStyle(
                  color: Color.fromARGB(200, 255, 255, 255),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLevelResults(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: game.distanceTracker,
      builder: (ctx, _) {
        final distanceTracker = Provider.of<DistanceTracker>(ctx);
        final team1Distance = distanceTracker.getFormattedDistance(0);
        final team2Distance = distanceTracker.getFormattedDistance(1);
        final team1Raw = distanceTracker.getTeamDistance(0);
        final team2Raw = distanceTracker.getTeamDistance(1);

        final winner = team1Raw > team2Raw
            ? 'Team 1'
            : (team2Raw > team1Raw ? 'Team 2' : 'Tie');

        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color.fromARGB(100, 60, 60, 60),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: [
              Text(
                'Level Results',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTeamResult('Team 1', team1Distance, winner == 'Team 1'),
                  _buildTeamResult('Team 2', team2Distance, winner == 'Team 2'),
                ],
              ),
              SizedBox(height: 15),
              Text(
                winner == 'Tie'
                    ? 'Level ended in a tie!'
                    : '$winner wins this level!',
                style: TextStyle(
                  color: winner == 'Tie'
                      ? Color.fromARGB(255, 255, 255, 0)
                      : Color.fromARGB(255, 0, 255, 0),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeamResult(String teamName, String distance, bool isWinner) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isWinner
            ? Color.fromARGB(100, 0, 255, 0)
            : Color.fromARGB(50, 100, 100, 100),
        borderRadius: BorderRadius.circular(10),
        border: isWinner
            ? Border.all(color: Color.fromARGB(255, 0, 255, 0), width: 2)
            : null,
      ),
      child: Column(
        children: [
          Text(
            teamName,
            style: TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 5),
          Text(
            distance,
            style: TextStyle(
              color: Color.fromARGB(200, 255, 255, 255),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isWinner) ...[
            SizedBox(height: 5),
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: Color.fromARGB(255, 0, 255, 0),
              size: 20,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTournamentProgress(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: game.tournamentManager,
      builder: (ctx, _) {
        final tournamentManager = Provider.of<TournamentManager>(ctx);

        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color.fromARGB(100, 60, 60, 60),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: [
              Text(
                'Tournament Score',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRoundWins('Team 1', tournamentManager.team1RoundWins),
                  _buildRoundWins('Team 2', tournamentManager.team2RoundWins),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoundWins(String teamName, int wins) {
    return Column(
      children: [
        Text(
          teamName,
          style: TextStyle(
            color: Color.fromARGB(255, 255, 255, 255),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 5),
        Text(
          '$wins round wins',
          style: TextStyle(
            color: Color.fromARGB(200, 255, 255, 255),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildReadyButton(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: game.tournamentManager,
      builder: (ctx, _) {
        final tournamentManager = Provider.of<TournamentManager>(ctx);
        final isComplete = tournamentManager.isTournamentComplete;

        return GestureDetector(
          onTap: _handleReady,
          child: Container(
            width: 200,
            height: 60,
            decoration: BoxDecoration(
              color: isComplete
                  ? Color.fromARGB(255, 255, 100, 0)
                  : // Orange for back to menu
                    Color.fromARGB(255, 0, 150, 255), // Blue for next level
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
                isComplete ? 'Back to Menu' : 'Ready for Next Level',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleReady() {
    appLog.info('Ready button pressed');

    if (game.tournamentManager.isTournamentComplete) {
      // Tournament is complete, go back to main menu
      game.overlays.remove(LevelTransitionUI.overlayID);
      game.overlays.add('MainMenu');
    } else {
      // Advance to next level
      _advanceToNextLevel();
    }
  }

  void _advanceToNextLevel() {
    appLog.info('Advancing to next level');

    // Remove this overlay
    game.overlays.remove(LevelTransitionUI.overlayID);

    // Reset level-specific state (but keep tournament progress)
    game.timeProvider.reset();
    game.distanceTracker.resetDistances();

    // Reset world controllers for next level
    for (final controller in game.worldControllers.values) {
      // also resets the world...as the controller is...the controller.
      (controller as Resetable).reset();
    }

    // Add the in-game UI overlay and resume game
    game.overlays.add('inGameUI');
    game.resumeEngine();
  }
}
