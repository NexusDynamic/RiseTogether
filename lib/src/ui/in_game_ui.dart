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
                final leftTeamId = game.getActualTeamId(0);
                final rightTeamId = game.getActualTeamId(1);
                final leftDistance = distanceTracker.getFormattedDistance(leftTeamId);
                final rightDistance = distanceTracker.getFormattedDistance(rightTeamId);
                
                return Text(
                  'My Team: $leftDistance | Opponent: $rightDistance',
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
                _buildProgressIndicator(context, game.getActualTeamId(0), screenHeight),
                SizedBox(width: 20),
                _buildProgressIndicator(context, game.getActualTeamId(1), screenHeight),
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
    // Get current player's team assignment from network coordinator
    final currentPlayerTeamId = _getCurrentPlayerTeamId();
    final currentPlayerTeam = Team.fromId(currentPlayerTeamId);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'My Team ${side.toUpperCase()}',
          style: const TextStyle(
            color: Color.fromARGB(150, 255, 255, 255),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            backgroundColor: Color.fromARGB(150, 0, 0, 0),
          ),
        ),
        const SizedBox(height: 10),
        _buildActionButton(
          teamId: currentPlayerTeamId, // Always use player's assigned team
          playerId: 'currentPlayer',
          action: side == 'left' ? PaddleAction.left : PaddleAction.right,
          icon: CupertinoIcons.arrow_up_to_line,
          color: getTeamColorWithOpacity(currentPlayerTeam, 0.8),
          size: 60,
        ),
      ],
    );
  }

  int _getCurrentPlayerTeamId() {
    // Get current player's team from action provider
    try {
      final currentAssignment = game.currentPlayerAssignment;
      if (currentAssignment == null) {
        throw StateError('Current player assignment not found');
      }
      appLog.info('UI: Current player assignment - Team: ${currentAssignment.teamId}, Player: ${currentAssignment.playerId}, Node: ${currentAssignment.nodeId}');
      return currentAssignment.teamId;
    } catch (e) {
      appLog.warning('Could not get current player team assignment: $e, defaulting to Team A');
      return Team.a.id; // Default to team A if network coordinator unavailable
    }
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
    // Get the actual teams for left and right display positions
    final leftTeamId = game.getActualTeamId(0);
    final rightTeamId = game.getActualTeamId(1);
    
    return [
      // Left team controls (Player's team)
      Positioned(
        left: 20,
        bottom: 50,
        child: _buildSimulatedTeamControls(
          team: Team.fromId(leftTeamId),
          screenHeight: screenHeight,
        ),
      ),
      // Right team controls (Opponent's team)
      Positioned(
        right: 20,
        bottom: 50,
        child: _buildSimulatedTeamControls(
          team: Team.fromId(rightTeamId),
          screenHeight: screenHeight,
        ),
      ),
    ];
  }

  Widget _buildSimulatedTeamControls({
    required Team team,
    required double screenHeight,
  }) {
    // Determine if this is the player's team or opponent
    final playerAssignment = game.currentPlayerAssignment;
    final isMyTeam = playerAssignment?.teamId == team.id;
    final teamLabel = isMyTeam ? 'My Team' : 'Opponent';
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          teamLabel,
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
    appLog.info(
      'UI sending action: team=$teamId, player=$playerId, action=$action',
    );
    game.sendAction(teamId, playerId, action);
  }
}
