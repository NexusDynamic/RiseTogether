import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/ui/in_game_ui.dart';
import 'package:rise_together/src/ui/main_menu_ui.dart';
import 'package:rise_together/src/ui/settings_ui.dart';
import 'package:rise_together/src/ui/level_transition_ui.dart';
import 'package:rise_together/src/ui/survey_ui.dart';
import 'package:rise_together/src/ui/coordination_ui.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/coordination_manager.dart';

class AnyInputScrollBehavior extends CupertinoScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class RiseTogetherApp extends StatefulWidget {
  const RiseTogetherApp({super.key});

  @override
  State<RiseTogetherApp> createState() => _RiseTogetherAppState();
}

class _RiseTogetherAppState extends State<RiseTogetherApp> with AppLogging {
  late final CoordinationManager coordinationManager;
  late final RiseTogetherGame game;

  @override
  void initState() {
    super.initState();
    coordinationManager = CoordinationManager();
    game = RiseTogetherGame();
    
    // Pass coordination manager to game
    game.coordinationManager = coordinationManager;

    // Initialize coordination manager asynchronously without blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCoordination();
    });
  }

  Future<void> _initializeCoordination() async {
    try {
      appLog.info('Starting coordination initialization...');
      await coordinationManager.initialize();
      appLog.info('Coordination initialization completed successfully');
    } catch (error) {
      appLog.severe('Failed to initialize coordination: $error');
      // Don't crash the app, just continue without network coordination
      appLog.warning('Continuing without network coordination');
    }
  }

  @override
  void dispose() {
    coordinationManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      scrollBehavior: AnyInputScrollBehavior(),
      home: GameWidget(
        game: game,
        initialActiveOverlays: const ['MainMenu'],
        overlayBuilderMap: {
          InGameUI.overlayID: (context, game) =>
              InGameUI(game as RiseTogetherGame),
          MainMenuUI.overlayID: (context, game) =>
              MainMenuUI(game as RiseTogetherGame, coordinationManager),
          SettingsUI.overlayID: (context, game) =>
              SettingsUI(game as RiseTogetherGame),
          LevelTransitionUI.overlayID: (context, game) =>
              LevelTransitionUI(game as RiseTogetherGame),
          SurveyUI.overlayID: (context, game) =>
              SurveyUI(game as RiseTogetherGame),
          CoordinationUI.overlayID: (context, game) =>
              CoordinationUI(game as RiseTogetherGame, coordinationManager),
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
