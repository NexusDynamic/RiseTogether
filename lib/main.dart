import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/version.dart';
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
import 'package:package_info_plus/package_info_plus.dart';

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
    appLog.info(
      'Starting RiseTogether (v${RiseTogetherPackageInfo.version}, '
      'build ${RiseTogetherPackageInfo.buildNumber})',
    );
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

      // Set up callback for when game actually starts (coordinated)
      networkCoordinator.setOnGameStartCallback(_onGameActuallyStarted);

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

      // Configure the action provider for all nodes
      await _actionProvider!.startGameplay();

      // UI transition will happen when game actually starts
      // For coordinator: after coordinated start sequence
      // For participants: when they receive start_game message
      appLog.info(
        'Action provider started - waiting for coordinated game start',
      );
    } catch (error) {
      appLog.severe('Failed to configure game: $error');
    }
  }

  /// Called when the game actually starts (after coordination)
  void _onGameActuallyStarted() async {
    appLog.info('Game actually started - transitioning UI');

    // Ensure game is configured before starting (important for participants)
    if (!game.isConfigured) {
      appLog.info('Game not configured yet, configuring now...');
      if (_actionProvider == null) {
        appLog.warning('Action provider not ready, using local provider');
        _actionProvider = LocalActionProvider();
        await _actionProvider!.initialize();
      }

      // Wait a moment for configuration to be fully received
      if (_actionProvider is NetworkActionProvider) {
        final networkCoordinator =
            (_actionProvider as NetworkActionProvider).networkCoordinator;
        appLog.info('Waiting for network configuration to be available...');

        // Check if we have received configuration
        final config = networkCoordinator.gameConfiguration;
        if (config == null) {
          appLog.warning(
            'No game configuration received from coordinator, using defaults',
          );
        } else {
          appLog.info(
            'Game configuration received from coordinator: ${config.keys.toList()}',
          );
        }
      }

      await game.configure(_actionProvider!);
      appLog.info('Game configured for participant');
    }

    // Always start the game engine components when this callback is triggered
    // This includes resumeEngine() and physics broadcasting
    await _startGameEngine();

    // Remove the main menu overlay
    game.overlays.remove('MainMenu');

    // Add the in-game UI overlay
    game.overlays.add('inGameUI');
  }

  /// Start the core game engine components
  Future<void> _startGameEngine() async {
    if (!game.isConfigured) {
      appLog.warning('Cannot start game engine - game not configured');
      return;
    }

    // Start physics state broadcasting if this is the coordinator
    if (_actionProvider is NetworkActionProvider) {
      final coordinator =
          (_actionProvider as NetworkActionProvider).networkCoordinator;
      if (coordinator.isCoordinator) {
        await coordinator.startPhysicsStateBroadcast();
        appLog.info('Physics state broadcasting started for coordinator');
      }
    }

    // Start the game engine
    game.resumeEngine();
    appLog.info('Game engine started');
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
          MainMenuUI.overlayID: (context, game) => MainMenuUI(
            game as RiseTogetherGame,
            networkCoordinator,
            configureAndStartGame,
          ),
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

void main() async {
  final _ = LogService();
  WidgetsFlutterBinding.ensureInitialized();
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  RiseTogetherPackageInfo().init(packageInfo);
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
