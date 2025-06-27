import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:provider/provider.dart';
import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/log_service.dart';

class InGameUI extends StatelessWidget
    with AppLogging
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
        child: ChangeNotifierProvider.value(
          value: game.timeProvider,
          builder: (ctx, _) => Text(
            'Time Passed:\n${Provider.of<TimeProvider>(ctx).formattedTime}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              backgroundColor: Color.fromARGB(150, 0, 0, 0),
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
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
      child: Row(
        children: [
          // Team 0 (Left side) controls
          SizedBox(width: 30),
          Expanded(
            child: _buildTeamSide(
              teamId: 0,
              teamName: 'Team 1',
              alignment: MainAxisAlignment.start,
              screenHeight: screenHeight,
            ),
          ),
          // Team 1 (Right side) controls
          Expanded(
            child: _buildTeamSide(
              teamId: 1,
              teamName: 'Team 2',
              alignment: MainAxisAlignment.end,
              screenHeight: screenHeight,
            ),
          ),
          SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _buildTeamSide({
    required int teamId,
    required String teamName,
    required MainAxisAlignment alignment,
    required double screenHeight,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: alignment == MainAxisAlignment.start
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            teamName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              backgroundColor: Color.fromARGB(150, 0, 0, 0),
            ),
          ),
        ),
        _buildPlayerControls(teamId, 'player1'),
        const SizedBox(height: 20),
        _buildPlayerControls(teamId, 'player2'),
        const SizedBox(height: 30),
      ],
    );
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
          color: Colors.orange.withAlpha(180),
        ),
        const SizedBox(width: 20),
        _buildActionButton(
          teamId: teamId,
          playerId: playerId,
          action: PaddleAction.right,
          icon: CupertinoIcons.arrow_up_to_line,
          color: Colors.blue.withAlpha(180),
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
  }) {
    return Listener(
      onPointerDown: (_) => _sendAction(teamId, playerId, action),
      onPointerUp: (_) => _sendAction(teamId, playerId, PaddleAction.none),
      onPointerCancel: (_) => _sendAction(teamId, playerId, PaddleAction.none),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              spreadRadius: 2,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 30),
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
