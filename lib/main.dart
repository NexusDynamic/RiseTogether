import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flame/game.dart';
import 'package:rise_together/src/ui/in_game_ui.dart';
import 'package:rise_together/src/game/rise_together_game.dart';

class RiseTogetherApp extends StatelessWidget {
  const RiseTogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: GameWidget(
        game: RiseTogetherGame(),
        overlayBuilderMap: {
          InGameUI.overlayID: (context, game) =>
              InGameUI(game as RiseTogetherGame),
        },
      ),
    );
  }
}

void main() {
  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en'), Locale('da')],
      path: 'assets/translations',
      fallbackLocale: Locale('en'),
      startLocale: Locale('da'),
      useOnlyLangCode: true,
      useFallbackTranslations: true,
      child: RiseTogetherApp(),
    ),
  );
}
