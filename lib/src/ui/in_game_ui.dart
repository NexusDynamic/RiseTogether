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

/// Manages button states for simulated player controls
class SimulatedPlayerController extends ChangeNotifier {
  final Map<String, PaddleAction> _activeActions = {};

  PaddleAction getPlayerAction(String playerId) {
    return _activeActions[playerId] ?? PaddleAction.none;
  }

  void setPlayerAction(String playerId, PaddleAction action) {
    if (_activeActions[playerId] != action) {
      _activeActions[playerId] = action;
      notifyListeners();
    }
  }

  void clearPlayerAction(String playerId) {
    if (_activeActions.containsKey(playerId)) {
      _activeActions.remove(playerId);
      notifyListeners();
    }
  }

  bool isPlayerActionActive(String playerId, PaddleAction action) {
    return _activeActions[playerId] == action;
  }
}

class InGameUI extends StatelessWidget
    with AppLogging, AppSettings, TeamColorProvider
    implements RiseTogetherOverlay {
  static final String overlayID = 'inGameUI';
  final RiseTogetherGame game;
  final SimulatedPlayerController _simulatedController =
      SimulatedPlayerController();

  InGameUI(this.game, {super.key});

  @override
  Widget build(BuildContext context) {
    appLog.info('Building InGameUI overlay');
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return ChangeNotifierProvider.value(
      value: _simulatedController,
      child: Stack(
        children: [
          _buildTimeDisplay(context, screenWidth),
          _buildTeamControls(context, screenWidth, screenHeight),
        ],
      ),
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
            SizedBox(height: 5),
            // If debug mode, show "DEMO MODE" text
            if (_isDebugMode())
              Text(
                'DEMO MODE',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  backgroundColor: Color.fromARGB(150, 0, 0, 0),
                  color: Color.fromARGB(255, 255, 0, 0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
          // Show either simulated or current player controls based on setting
          if (_isSimulatedMode())
            ..._buildSimulatedPlayerControls(screenWidth, screenHeight)
          else ...[
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
          ],
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

  bool _isSimulatedMode() {
    try {
      return appSettings.getBool('game.simulated_players');
    } catch (e) {
      // Fallback to false if setting is not available
      appLog.warning('Could not access simulated_players setting: $e');
      return false;
    }
  }

  bool _isDebugMode() {
    try {
      return appSettings.getBool('game.debug_mode');
    } catch (e) {
      // Fallback to false if setting is not available
      appLog.warning('Could not access debug.enabled setting: $e');
      return false;
    }
  }

  List<Widget> _buildSimulatedPlayerControls(
    double screenWidth,
    double screenHeight,
  ) {
    return [
      // Left team controls (Team A)
      Positioned(
        left: 20,
        bottom: 50,
        child: _buildSimulatedTeamControls(
          team: Team.a,
          screenHeight: screenHeight,
        ),
      ),
      // Right team controls (Team B)
      Positioned(
        right: 20,
        bottom: 50,
        child: _buildSimulatedTeamControls(
          team: Team.b,
          screenHeight: screenHeight,
        ),
      ),
    ];
  }

  Widget _buildSimulatedTeamControls({
    required Team team,
    required double screenHeight,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          team.shortName,
          style: const TextStyle(
            color: Color.fromARGB(200, 255, 255, 255),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            backgroundColor: Color.fromARGB(150, 0, 0, 0),
          ),
        ),
        const SizedBox(height: 15),
        // Players side-by-side
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Player 1 controls
            _buildSimulatedPlayerRow(
              team: team,
              playerId: 'P${team.id * 2 + 1}',
              playerLabel: 'P${team.id * 2 + 1} (iPad${team.id * 2 + 1})',
              screenHeight: screenHeight,
            ),
            const SizedBox(width: 30),
            // Player 2 controls
            _buildSimulatedPlayerRow(
              team: team,
              playerId: 'P${team.id * 2 + 2}',
              playerLabel: 'P${team.id * 2 + 2} (iPad${team.id * 2 + 2})',
              screenHeight: screenHeight,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSimulatedPlayerRow({
    required Team team,
    required String playerId,
    required String playerLabel,
    required double screenHeight,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          playerLabel,
          style: const TextStyle(
            color: Color.fromARGB(200, 255, 255, 255),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            backgroundColor: Color.fromARGB(100, 0, 0, 0),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionButton(
              teamId: team.id,
              playerId: playerId,
              action: PaddleAction.left,
              icon: CupertinoIcons.arrow_up_left,
              color: getTeamColorWithOpacity(team, 0.8),
              size: 55,
            ),
            const SizedBox(width: 25),
            _buildActionButton(
              teamId: team.id,
              playerId: playerId,
              action: PaddleAction.right,
              icon: CupertinoIcons.arrow_up_right,
              color: getTeamAccentColor(team).withValues(alpha: 0.8),
              size: 55,
            ),
          ],
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
    return Consumer<SimulatedPlayerController>(
      builder: (context, controller, child) {
        final isActive = controller.isPlayerActionActive(playerId, action);
        final effectiveColor = isActive ? color : color.withValues(alpha: 0.5);

        return Listener(
          onPointerDown: (_) =>
              _handleActionPress(teamId, playerId, action, controller),
          onPointerUp: (_) =>
              _handleActionRelease(teamId, playerId, controller),
          onPointerCancel: (_) =>
              _handleActionRelease(teamId, playerId, controller),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: effectiveColor,
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(
                      color: Color.fromARGB(255, 255, 255, 255),
                      width: 2,
                    )
                  : null,
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
              color: Color.fromARGB(255, 255, 255, 255),
              size: size * 0.6,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  void _handleActionPress(
    int teamId,
    String playerId,
    PaddleAction action,
    SimulatedPlayerController controller,
  ) {
    // Set the action in the controller (this will clear any other action for this player)
    controller.setPlayerAction(playerId, action);
    // Send the action to the game
    _sendAction(teamId, playerId, action);
  }

  void _handleActionRelease(
    int teamId,
    String playerId,
    SimulatedPlayerController controller,
  ) {
    // Clear the action in the controller
    controller.clearPlayerAction(playerId);
    // Send none action to the game
    _sendAction(teamId, playerId, PaddleAction.none);
  }

  void _sendAction(int teamId, String playerId, PaddleAction action) {
    appLog.fine(
      'UI sending action: team=$teamId, player=$playerId, action=$action',
    );
    game.networkBridge.sendAction(teamId, playerId, action);
  }
}
