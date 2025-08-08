import 'dart:async';

import 'package:rise_together/src/models/player_action.dart';
import 'package:rise_together/src/models/team_thrust.dart';

/// Manages action streams for a specific team
class TeamActionStream {
  final int teamId;
  final int maxPlayers;
  final StreamController<GameAction> _controller =
      StreamController<GameAction>.broadcast();
  final Map<String, PaddleAction> _currentActions = {};

  Stream<GameAction> get actionStream => _controller.stream;
  Stream<TeamThrust> get thrustStream =>
      _controller.stream.map((_) => _calculateThrust());

  TeamActionStream({required this.teamId, required this.maxPlayers});

  void addAction(GameAction action) {
    _currentActions[action.playerId] = action.action;
    _controller.add(action);
  }

  void removePlayer(String playerId) {
    _currentActions.remove(playerId);
    _controller.add(GameAction(playerId, PaddleAction.none));
  }

  TeamThrust _calculateThrust() {
    final actions = _currentActions.values.toList();
    final leftCount = actions.where((a) => a == PaddleAction.left).length;
    final rightCount = actions.where((a) => a == PaddleAction.right).length;
    final activeCount = leftCount + rightCount;

    final thrustPerPlayer = 1.0 / maxPlayers;

    return TeamThrust(
      leftThrust: leftCount * thrustPerPlayer,
      rightThrust: rightCount * thrustPerPlayer,
      activePlayerCount: activeCount,
    );
  }

  TeamThrust getCurrentThrust() => _calculateThrust();

  void dispose() {
    _controller.close();
  }
}

/// Manages multiple team action streams
class ActionStreamManager {
  final Map<int, TeamActionStream> _teamStreams = {};

  TeamActionStream createTeamStream(int teamId, int maxPlayers) {
    final stream = TeamActionStream(teamId: teamId, maxPlayers: maxPlayers);
    _teamStreams[teamId] = stream;
    return stream;
  }

  TeamActionStream? getTeamStream(int teamId) => _teamStreams[teamId];

  void dispose() {
    for (final stream in _teamStreams.values) {
      stream.dispose();
    }
    _teamStreams.clear();
  }
}
