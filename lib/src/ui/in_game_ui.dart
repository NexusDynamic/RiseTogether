import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/models/team.dart';
import 'package:rise_together/src/attributes/team_color_provider.dart';
import 'package:rise_together/src/ui/level_progress.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/game/tournament_manager.dart';
import 'package:rise_together/src/game/distance_tracker.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/settings/app_settings.dart';

class InGameUI extends StatelessWidget
    with AppLogging, AppSettings, TeamColorProvider
    implements RiseTogetherOverlay {
  static final String overlayID = 'inGameUI';
  final RiseTogetherGame game;
  InGameUI(this.game, {super.key});

  @override
  Widget build(BuildContext context) {
    appLog.info('Building InGameUI overlay');
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        _buildTimeDisplay(context, screenWidth),
        _buildTeamControls(context, screenWidth, screenHeight),
      ],
    );
  }

  Widget _buildTimeDisplay(BuildContext context, double screenWidth) {
    return Positioned(
      top: 10,
      width: screenWidth,
      child: Center(
        child: Column(
          children: [
            // Tournament Progress
            ChangeNotifierProvider.value(
              value: game.tournamentManager,
              builder: (ctx, _) {
                final tournamentManager = Provider.of<TournamentManager>(ctx);
                return Text(
                  tournamentManager.levelProgress,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    backgroundColor: Color.fromARGB(150, 0, 0, 0),
                    color: Color.fromARGB(200, 255, 255, 255),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
            SizedBox(height: 5),
            // Time Remaining
            ChangeNotifierProvider.value(
              value: game.timeProvider,
              builder: (ctx, _) => Text(
                'Time: ${Provider.of<TimeProvider>(ctx).formattedTime}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  backgroundColor: Color.fromARGB(150, 0, 0, 0),
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: 5),
            // Distance Display
            ChangeNotifierProvider.value(
              value: game.distanceTracker,
              builder: (ctx, _) {
                final distanceTracker = Provider.of<DistanceTracker>(ctx);
                return Text(
                  'Team 1: ${distanceTracker.getFormattedDistance(0)} | Team 2: ${distanceTracker.getFormattedDistance(1)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    backgroundColor: Color.fromARGB(150, 0, 0, 0),
                    color: Color.fromARGB(200, 255, 255, 255),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamControls(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Progress indicators in center
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProgressIndicator(context, Team.a.id, screenHeight),
                SizedBox(width: 20),
                _buildProgressIndicator(context, Team.b.id, screenHeight),
              ],
            ),
          ),
          // Current player controls - Left side
          Positioned(
            left: 20,
            bottom: 50,
            child: _buildCurrentPlayerControls(
              side: 'left',
              screenHeight: screenHeight,
            ),
          ),
          // Current player controls - Right side
          Positioned(
            right: 20,
            bottom: 50,
            child: _buildCurrentPlayerControls(
              side: 'right',
              screenHeight: screenHeight,
            ),
          ),
          // Debug controls at bottom center (if debug mode enabled)
          if (_isDebugMode())
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: _buildDebugControls(screenHeight),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(
    BuildContext context,
    int teamId,
    double screenHeight,
  ) {
    return LevelProgressMeter(game: game, teamId: teamId);
  }

  Widget _buildCurrentPlayerControls({
    required String side,
    required double screenHeight,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          side == 'left' ? Team.a.shortName : Team.b.shortName,
          style: const TextStyle(
            color: Color.fromARGB(150, 255, 255, 255),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            backgroundColor: Color.fromARGB(150, 0, 0, 0),
          ),
        ),
        const SizedBox(height: 10),
        _buildActionButton(
          teamId: side == 'left' ? Team.a.id : Team.b.id,
          playerId: 'currentPlayer',
          action: side == 'left' ? PaddleAction.left : PaddleAction.right,
          icon: CupertinoIcons.arrow_up_to_line,
          color: side == 'left' 
            ? getTeamColorWithOpacity(Team.a, 0.8)
            : getTeamColorWithOpacity(Team.b, 0.8),
          size: 60,
        ),
      ],
    );
  }

  Widget _buildDebugControls(double screenHeight) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Debug Controls',
            style: const TextStyle(
              color: Color.fromARGB(150, 255, 255, 255),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              backgroundColor: Color.fromARGB(150, 0, 0, 0),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                children: [
                  Text(Team.a.shortName, style: TextStyle(color: Color.fromARGB(150, 255, 255, 255), fontSize: 12)),
                  _buildPlayerControls(Team.a.id, 'player1'),
                  const SizedBox(height: 10),
                  _buildPlayerControls(Team.a.id, 'player2'),
                ],
              ),
              const SizedBox(width: 40),
              Column(
                children: [
                  Text(Team.b.shortName, style: TextStyle(color: Color.fromARGB(150, 255, 255, 255), fontSize: 12)),
                  _buildPlayerControls(Team.b.id, 'player1'),
                  const SizedBox(height: 10),
                  _buildPlayerControls(Team.b.id, 'player2'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isDebugMode() {
    try {
      return appSettings.getBool('game.debug_mode');
    } catch (e) {
      // Fallback to false if setting is not available
      appLog.warning('Could not access debug_mode setting: $e');
      return false;
    }
  }

  Widget _buildPlayerControls(int teamId, String playerId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          teamId: teamId,
          playerId: playerId,
          action: PaddleAction.left,
          icon: CupertinoIcons.arrow_up_to_line,
          color: getTeamColorWithOpacity(Team.fromId(teamId), 0.7),
        ),
        const SizedBox(width: 20),
        _buildActionButton(
          teamId: teamId,
          playerId: playerId,
          action: PaddleAction.right,
          icon: CupertinoIcons.arrow_up_to_line,
          color: getTeamAccentColor(Team.fromId(teamId)).withValues(alpha: 0.7),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required int teamId,
    required String playerId,
    required PaddleAction action,
    required IconData icon,
    required Color color,
    double size = 40,
  }) {
    return Listener(
      onPointerDown: (_) => _sendAction(teamId, playerId, action),
      onPointerUp: (_) => _sendAction(teamId, playerId, PaddleAction.none),
      onPointerCancel: (_) => _sendAction(teamId, playerId, PaddleAction.none),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB(150, 0, 0, 0),
              spreadRadius: 2,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Color.fromARGB(255, 0, 0, 0),
          size: size * 0.6,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _sendAction(int teamId, String playerId, PaddleAction action) {
    appLog.fine(
      'UI sending action: team=$teamId, player=$playerId, action=$action',
    );
    game.networkBridge.sendAction(teamId, playerId, action);
  }
}
