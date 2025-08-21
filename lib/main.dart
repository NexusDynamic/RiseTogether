import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/settings/app_settings.dart';
import 'package:rise_together/src/ui/in_game_ui.dart';
import 'package:rise_together/src/ui/main_menu_ui.dart';
import 'package:rise_together/src/ui/settings_ui.dart';
import 'package:rise_together/src/ui/level_transition_ui.dart';
import 'package:rise_together/src/ui/survey_ui.dart';
import 'package:rise_together/src/ui/coordination_ui.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/network_coordinator.dart';
import 'package:rise_together/src/game/action_provider.dart';

class AnyInputScrollBehavior extends CupertinoScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class RiseTogetherApp extends StatefulWidget with AppSettings {
  RiseTogetherApp({super.key}) {
    initSettings();
  }

  @override
  State<RiseTogetherApp> createState() => _RiseTogetherAppState();
}

class _RiseTogetherAppState extends State<RiseTogetherApp>
    with AppLogging, AppSettings {
  late final NetworkCoordinator networkCoordinator;
  late final RiseTogetherGame game;
  ActionProvider? _actionProvider;

  @override
  void initState() {
    super.initState();
    game = RiseTogetherGame();
    initSettings().then((_) {
      networkCoordinator = NetworkCoordinator();

      // Initialize coordination layer early (app level)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeCoordination();
      });
    });
  }

  Future<void> _initializeCoordination() async {
    try {
      appLog.info('Starting coordination initialization...');
      await networkCoordinator.initialize();
      appLog.info('Coordination initialization completed successfully');
      
      // Create action provider but don't configure game yet
      // Game will be configured when user starts a game from menu
      _actionProvider = NetworkActionProvider(networkCoordinator);
      appLog.info('Action provider created and ready');
    } catch (error) {
      appLog.severe('Failed to initialize coordination: $error');
      // Fall back to local action provider
      _actionProvider = LocalActionProvider();
      appLog.warning('Using local action provider as fallback');
    }
  }

  /// Configure and start game (called from menu)
  Future<void> configureAndStartGame() async {
    if (_actionProvider == null) {
      appLog.warning('Action provider not ready, using local provider');
      _actionProvider = LocalActionProvider();
    }

    try {
      await game.configure(_actionProvider!);
      appLog.info('Game configured with action provider');
      
      // Only start if this node is the coordinator
      if (_actionProvider!.isCoordinator) {
        await game.startGame();
        appLog.info('Game started by coordinator');
      } else {
        appLog.info('Waiting for coordinator to start game');
      }
    } catch (error) {
      appLog.severe('Failed to configure game: $error');
    }
  }

  @override
  void dispose() {
    _actionProvider?.dispose();
    networkCoordinator.dispose();
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
              MainMenuUI(game as RiseTogetherGame, networkCoordinator, configureAndStartGame),
          SettingsUI.overlayID: (context, game) =>
              SettingsUI(game as RiseTogetherGame),
          LevelTransitionUI.overlayID: (context, game) =>
              LevelTransitionUI(game as RiseTogetherGame),
          SurveyUI.overlayID: (context, game) =>
              SurveyUI(game as RiseTogetherGame),
          CoordinationUI.overlayID: (context, game) =>
              CoordinationUI(game as RiseTogetherGame, networkCoordinator),
        },
      ),
    );
  }
}

void main() {
  final _ = LogService();
  WidgetsFlutterBinding.ensureInitialized();
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
