import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:rise_together/src/ui/in_game_ui.dart';
import 'package:rise_together/src/ui/main_menu_ui.dart';
import 'package:rise_together/src/ui/settings_ui.dart';
import 'package:rise_together/src/ui/level_transition_ui.dart';
import 'package:rise_together/src/ui/survey_ui.dart';
import 'package:rise_together/src/game/rise_together_game.dart';

class AnyInputScrollBehavior extends CupertinoScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class RiseTogetherApp extends StatelessWidget {
  const RiseTogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      scrollBehavior: AnyInputScrollBehavior(),
      home: GameWidget(
        game: RiseTogetherGame(),
        initialActiveOverlays: const ['MainMenu'],
        overlayBuilderMap: {
          InGameUI.overlayID: (context, game) =>
              InGameUI(game as RiseTogetherGame),
          MainMenuUI.overlayID: (context, game) =>
              MainMenuUI(game as RiseTogetherGame),
          SettingsUI.overlayID: (context, game) =>
              SettingsUI(game as RiseTogetherGame),
          LevelTransitionUI.overlayID: (context, game) =>
              LevelTransitionUI(game as RiseTogetherGame),
          SurveyUI.overlayID: (context, game) =>
              SurveyUI(game as RiseTogetherGame),
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
