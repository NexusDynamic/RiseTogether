import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rise_together/src/components/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/log_service.dart';

class InGameUI extends StatelessWidget
    with AppLogging
    implements RiseTogetherOverlay {
  static final String overlayID = 'inGameUI';
  final RiseTogetherGame game;
  InGameUI(this.game, {super.key});

  /// right now, a simple UI that shows the elasped time only (game.timePassed)
  @override
  Widget build(BuildContext context) {
    appLog.info('Building InGameUI overlay');
    return Stack(
      children: [
        Positioned(
          top: 10,
          // height: 50,
          width: MediaQuery.of(context).size.width,
          child: Center(
            child: ChangeNotifierProvider.value(
              value: game.timeProvider,
              builder: (ctx, _) => Text(
                'Time Passed:\n${Provider.of<TimeProvider>(ctx).formattedTime}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  backgroundColor: Color.fromARGB(150, 0, 0, 0),
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        // Circular buttons on bottom left and right corners
        Positioned(
          bottom: 10,
          left: 10,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              // Handle left button action
              game.pressedKeySet.add(LogicalKeyboardKey.arrowLeft);
            },
            onPointerUp: (event) {
              // Handle left button release
              game.pressedKeySet.remove(LogicalKeyboardKey.arrowLeft);
            },
            child: FloatingActionButton(
              onPressed: () {
                // Handle right button action
              },
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          right: 10,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              // Handle left button action
              game.pressedKeySet.add(LogicalKeyboardKey.arrowRight);
            },
            onPointerUp: (event) {
              // Handle left button release
              game.pressedKeySet.remove(LogicalKeyboardKey.arrowRight);
            },
            child: FloatingActionButton(
              onPressed: () {
                // Handle right button action
              },
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        ),
      ],
    );
  }
}
