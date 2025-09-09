import 'package:flutter/foundation.dart';
import 'package:rise_together/src/attributes/resetable.dart';
import 'package:rise_together/src/models/team.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Tracks distance traveled by teams based on ball position
class DistanceTracker extends ChangeNotifier with AppLogging, Resetable {
  double _distanceMultiplier = 100.0; // Default: 100 meters per game unit
  final Map<int, double> _maxDistances =
      {}; // team ID -> max distance in meters
  final Map<int, double> _startingHeights = {}; // team ID -> starting height

  // For throttling UI updates
  DateTime _lastUpdate = DateTime.now();
  static const _updateThreshold = Duration.zero;
  // static const _updateThreshold = Duration(milliseconds: 100); // Update UI max 10 times per second

  double get distanceMultiplier => _distanceMultiplier;
  Map<int, double> get maxDistances => Map.unmodifiable(_maxDistances);

  void initialize(double multiplier) {
    _distanceMultiplier = multiplier;
    appLog.info(
      'Distance tracker initialized with multiplier: $_distanceMultiplier',
    );
  }

  /// Set the starting height for a team (typically 0, but may vary by level)
  void setStartingHeight(int teamId, double height) {
    _startingHeights[teamId] = height;
    _maxDistances[teamId] =
        0.0; // Reset max distance when starting height changes
    appLog.fine('Team $teamId starting height set to $height');
  }

  /// Update the current ball position for a team and track max distance
  void updateBallPosition(int teamId, double currentHeight) {
    final startHeight = _startingHeights[teamId] ?? 0.0;
    final relativeHeight = currentHeight.abs() - startHeight.abs();

    final distanceInMeters = relativeHeight * _distanceMultiplier;

    // Only track positive distances (upward movement)
    final positiveDistance = distanceInMeters > 0 ? distanceInMeters : 0.0;

    bool shouldNotify = false;

    if (positiveDistance > (_maxDistances[teamId] ?? 0.0)) {
      _maxDistances[teamId] = positiveDistance;
      // appLog.fine(
      //   'Team $teamId new max distance: ${positiveDistance.toStringAsFixed(1)}m',
      // );
      shouldNotify = true;
    }

    // Throttle UI updates to avoid excessive redraws
    final now = DateTime.now();
    if (shouldNotify || now.difference(_lastUpdate) > _updateThreshold) {
      _lastUpdate = now;
      notifyListeners();
    }
  }

  /// Get the current max distance for a team in meters
  double getTeamDistance(int teamId) {
    return _maxDistances[teamId] ?? 0.0;
  }

  /// Get formatted distance string for display
  String getFormattedDistance(int teamId) {
    final distance = getTeamDistance(teamId);
    return distance.toStringAsFixed(1);
  }

  /// Get the current max distance for a team by Team enum
  double getDistanceForTeam(Team team) {
    return getTeamDistance(team.id);
  }

  /// Get formatted distance string for display by Team enum
  String getFormattedDistanceForTeam(Team team) {
    return getFormattedDistance(team.id);
  }

  /// Set starting height by Team enum
  void setStartingHeightForTeam(Team team, double height) {
    setStartingHeight(team.id, height);
  }

  /// Update ball position by Team enum
  void updateBallPositionForTeam(Team team, double currentHeight) {
    updateBallPosition(team.id, currentHeight);
  }

  /// Get both team distances for level completion
  Map<int, double> getAllDistances() {
    return Map.from(_maxDistances);
  }

  @override
  void reset() {
    _maxDistances.clear();
    _startingHeights.clear();
    // Initialize for both teams
    for (final team in Team.values) {
      _maxDistances[team.id] = 0.0;
      _startingHeights[team.id] = 0.0;
    }
    appLog.info('Distance tracker reset');
    notifyListeners();
  }

  /// Reset only distances (keep starting heights for level restart)
  void resetDistances() {
    for (final team in Team.values) {
      _maxDistances[team.id] = 0.0;
    }
    appLog.info('Distance tracker distances reset');
    notifyListeners();
  }
}
