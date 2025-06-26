/// Action types that players can contribute to the paddle
enum PaddleAction { left, right, none }

/// Represents an action from a specific player
class PlayerAction {
  final String playerId;
  final PaddleAction action;
  final DateTime timestamp;

  PlayerAction(this.playerId, this.action) : timestamp = DateTime.now();

  @override
  String toString() => 'PlayerAction($playerId, $action)';
}
