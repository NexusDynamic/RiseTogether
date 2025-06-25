import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:rise_together/src/components/in_game_ui.dart';
import 'package:rise_together/src/game/rise_together_game.dart';

void main() {
  runApp(
    GameWidget(
      game: RiseTogetherGame(),
      overlayBuilderMap: {
        InGameUI.overlayID: (context, game) =>
            InGameUI(game as RiseTogetherGame),
      },
    ),
  );
}
