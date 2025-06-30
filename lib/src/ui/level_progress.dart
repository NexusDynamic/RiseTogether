import 'package:flutter/cupertino.dart';
import 'package:rise_together/src/game/rise_together_game.dart';

/// A widget that displays a level progress meter
/// This is a vertical "elevator" style progress bar (similar to a scrollbar)
/// that shows how much distance the player has travelled. This will be
/// used to show and compare progress between the two teams.
class LevelProgressMeter extends StatelessWidget {
  final int teamId;
  final RiseTogetherGame game;

  const LevelProgressMeter({required this.game, this.teamId = 0, super.key})
    : super();
  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.of(context).size.height * 0.8; // 80% of screen height

    return SizedBox(
      width: 10,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 10,
            height: height,
            color: const Color.fromARGB(150, 127, 127, 127),
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable:
                      game.worldControllers[teamId].paddle.positionNotifier,
                  builder: (context, position, child) {
                    final progress = game.worldControllers[teamId]
                        .levelProgress(position);

                    return Positioned(
                      bottom: (height - (height * 0.05)) * progress,
                      left: 1,
                      child: Container(
                        width: 8,
                        height: height * 0.05,

                        color: Color.fromARGB(255, 255, 255, 255),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
