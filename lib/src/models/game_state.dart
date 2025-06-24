import 'dart:convert';
import 'package:flame/components.dart';

class TeamState {
  final String teamId;
  double distance = 0.0;
  Vector2 ballPosition;
  Vector2 paddlePosition;
  double paddleAngle = 0.0;
  Map<String, String> playerInputs =
      {}; // participantId -> "left", "right", "none"
  bool ballDropped = false;

  TeamState({
    required this.teamId,
    required this.ballPosition,
    required this.paddlePosition,
  });

  Map<String, dynamic> toJson() {
    return {
      'teamId': teamId,
      'distance': distance,
      'ballPosition': [ballPosition.x, ballPosition.y],
      'paddlePosition': [paddlePosition.x, paddlePosition.y],
      'paddleAngle': paddleAngle,
      'playerInputs': playerInputs,
      'ballDropped': ballDropped,
    };
  }

  factory TeamState.fromJson(Map<String, dynamic> json) {
    final state = TeamState(
      teamId: json['teamId'],
      ballPosition: Vector2(json['ballPosition'][0], json['ballPosition'][1]),
      paddlePosition: Vector2(
        json['paddlePosition'][0],
        json['paddlePosition'][1],
      ),
    );
    state.distance = json['distance'];
    state.paddleAngle = json['paddleAngle'];
    state.playerInputs = Map<String, String>.from(json['playerInputs']);
    state.ballDropped = json['ballDropped'];
    return state;
  }

  String encode() {
    return jsonEncode(toJson());
  }

  static TeamState decode(String data) {
    return TeamState.fromJson(jsonDecode(data));
  }
}

class GameState {
  final TeamState localTeam;
  TeamState? remoteTeam;
  double timeRemaining = 120.0; // 2 minutes countdown
  bool gameActive = false;

  GameState({required this.localTeam, this.remoteTeam});

  Map<String, dynamic> toJson() {
    final result = {
      'localTeam': localTeam.toJson(),
      'timeRemaining': timeRemaining,
      'gameActive': gameActive,
    };

    if (remoteTeam != null) {
      result['remoteTeam'] = remoteTeam!.toJson();
    }

    return result;
  }

  String encode() {
    return jsonEncode(toJson());
  }
}
