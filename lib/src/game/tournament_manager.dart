import 'package:flutter/foundation.dart';
import 'package:rise_together/src/attributes/resetable.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Represents the score and progress for a single level
class LevelResult {
  final int levelIndex;
  final double team1Distance;
  final double team2Distance;
  final int winningTeam; // 0 for team1, 1 for team2, -1 for tie

  LevelResult({
    required this.levelIndex,
    required this.team1Distance,
    required this.team2Distance,
  }) : winningTeam = team1Distance > team2Distance
           ? 0
           : (team2Distance > team1Distance ? 1 : -1);

  String get formattedResult =>
      'Level ${levelIndex + 1}: Team 1: ${team1Distance.toStringAsFixed(1)}m, '
      'Team 2: ${team2Distance.toStringAsFixed(1)}m - '
      '${winningTeam == -1 ? "Tie" : "Team ${winningTeam + 1} wins"}';
}

/// Represents a complete round (set of levels)
class RoundResult {
  final int roundIndex;
  final List<LevelResult> levelResults;

  RoundResult({required this.roundIndex, required this.levelResults});

  int get team1Wins => levelResults.where((r) => r.winningTeam == 0).length;
  int get team2Wins => levelResults.where((r) => r.winningTeam == 1).length;
  int get ties => levelResults.where((r) => r.winningTeam == -1).length;

  int get roundWinner =>
      team1Wins > team2Wins ? 0 : (team2Wins > team1Wins ? 1 : -1);

  bool get isComplete =>
      levelResults.length >= 5; // Assuming 5 levels per round for now
}

/// Manages tournament progress, scoring, and state
class TournamentManager extends ChangeNotifier with AppLogging, Resetable {
  int _currentRound = 0;
  int _currentLevel = 0;
  int _totalRounds = 3;
  int _levelsPerRound = 5;

  final List<RoundResult> _roundResults = [];
  final Map<int, double> _currentLevelDistances = {
    0: 0.0,
    1: 0.0,
  }; // team -> max distance

  // Getters
  int get currentRound => _currentRound;
  int get currentLevel => _currentLevel;
  int get totalRounds => _totalRounds;
  int get levelsPerRound => _levelsPerRound;
  List<RoundResult> get roundResults => List.unmodifiable(_roundResults);
  Map<int, double> get currentLevelDistances =>
      Map.unmodifiable(_currentLevelDistances);

  bool get isLevelComplete => false; // Will be set by game logic
  bool get isRoundComplete => _currentLevel >= _levelsPerRound;
  bool get isTournamentComplete => _currentRound >= _totalRounds;

  /// Current level progress display (1-indexed)
  String get levelProgress =>
      'Round ${_currentRound + 1}/$_totalRounds - Level ${_currentLevel + 1}/$_levelsPerRound';

  /// Tournament wins for each team
  int get team1RoundWins =>
      _roundResults.where((r) => r.roundWinner == 0).length;
  int get team2RoundWins =>
      _roundResults.where((r) => r.roundWinner == 1).length;

  void initialize(int rounds, int levelsPerRound) {
    _totalRounds = rounds;
    _levelsPerRound = levelsPerRound;
    _currentRound = 0;
    _currentLevel = 0;
    _roundResults.clear();
    _currentLevelDistances.clear();
    _currentLevelDistances[0] = 0.0;
    _currentLevelDistances[1] = 0.0;
    appLog.info(
      'Tournament initialized: $_totalRounds rounds x $_levelsPerRound levels',
    );
    notifyListeners();
  }

  /// Update the maximum distance achieved by a team in the current level
  void updateTeamDistance(int teamId, double distance) {
    if (_currentLevelDistances[teamId] == null ||
        distance > _currentLevelDistances[teamId]!) {
      _currentLevelDistances[teamId] = distance;
      notifyListeners();
    }
  }

  /// Complete the current level and determine winner
  void completeLevel() {
    if (isTournamentComplete) return;

    final levelResult = LevelResult(
      levelIndex: _currentLevel,
      team1Distance: _currentLevelDistances[0] ?? 0.0,
      team2Distance: _currentLevelDistances[1] ?? 0.0,
    );

    // Add to current round or create new round
    if (_roundResults.length <= _currentRound) {
      _roundResults.add(
        RoundResult(roundIndex: _currentRound, levelResults: [levelResult]),
      );
    } else {
      _roundResults[_currentRound].levelResults.add(levelResult);
    }

    appLog.info('Level completed: ${levelResult.formattedResult}');

    // Reset level distances for next level
    _currentLevelDistances[0] = 0.0;
    _currentLevelDistances[1] = 0.0;

    // Advance to next level
    _currentLevel++;

    // Check if round is complete
    if (isRoundComplete) {
      _completeRound();
    }

    notifyListeners();
  }

  void _completeRound() {
    final currentRoundResult = _roundResults[_currentRound];
    appLog.info(
      'Round ${_currentRound + 1} complete: Team 1: ${currentRoundResult.team1Wins} wins, Team 2: ${currentRoundResult.team2Wins} wins',
    );

    _currentRound++;
    _currentLevel = 0;

    if (isTournamentComplete) {
      _completeTournament();
    }
  }

  void _completeTournament() {
    appLog.info(
      'Tournament complete! Team 1 round wins: $team1RoundWins, Team 2 round wins: $team2RoundWins',
    );
    final tournamentWinner = team1RoundWins > team2RoundWins
        ? 1
        : (team2RoundWins > team1RoundWins ? 2 : 0);
    if (tournamentWinner > 0) {
      appLog.info('Tournament winner: Team $tournamentWinner');
    } else {
      appLog.info('Tournament ended in a tie');
    }
  }

  @override
  void reset() {
    _currentRound = 0;
    _currentLevel = 0;
    _roundResults.clear();
    _currentLevelDistances[0] = 0.0;
    _currentLevelDistances[1] = 0.0;
    appLog.info('Tournament reset');
    notifyListeners();
  }

  /// Reset only the current level (for level restart)
  void resetLevel() {
    _currentLevelDistances[0] = 0.0;
    _currentLevelDistances[1] = 0.0;
    appLog.info('Level reset');
    notifyListeners();
  }
}
