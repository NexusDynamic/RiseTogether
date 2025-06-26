/// Aggregated thrust data for a team
class TeamThrust {
  final double leftThrust;
  final double rightThrust;
  final double netThrust;
  final int activePlayerCount;

  TeamThrust({
    required this.leftThrust,
    required this.rightThrust,
    required this.activePlayerCount,
  }) : netThrust = rightThrust - leftThrust;

  @override
  String toString() =>
      'TeamThrust(left: $leftThrust, right: $rightThrust, net: $netThrust, players: $activePlayerCount)';
}
