import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:rise_together/src/game/action_system.dart';
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
import 'package:flutter/services.dart';
import 'package:rise_together/src/services/headless_config_service.dart';
import 'package:rise_together/src/services/headless_api_controller.dart';

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
  final bool headlessMode;
  RiseTogetherApp({super.key, this.headlessMode = false}) {
    initSettings();
  }

  @override
  State<RiseTogetherApp> createState() => _RiseTogetherAppState();
}

class _RiseTogetherAppState extends State<RiseTogetherApp>
    with AppLogging, AppSettings {
  final ActionStreamManager _actionManager = ActionStreamManager();
  late final NetworkCoordinator networkCoordinator;
  late final RiseTogetherGame game;
  ActionProvider? _actionProvider;

  // Headless mode services
  HeadlessConfigService? _headlessService;
  HeadlessApiController? _apiController;

  @override
  void initState() {
    super.initState();
    appLog.info(
      'Starting RiseTogether (v${RiseTogetherPackageInfo.version}, '
      'build ${RiseTogetherPackageInfo.buildNumber})',
    );
    networkCoordinator = NetworkCoordinator(_actionManager);
    game = RiseTogetherGame(actionManager: _actionManager);

    _initializeCoordination();
  }

  Future<void> _setupHeadlessFeatures() async {
    if (!(_headlessService?.isHeadlessMode ?? false)) return;

    appLog.info('Setting up headless features');

    // Set up API controller
    _apiController = HeadlessApiController(
      coordinator: networkCoordinator,
      game: game,
      startGameCallback: configureAndStartGame,
      stopGameCallback: () async {
        await game.stopGame();
      },
      port: _headlessService!.config.httpApiPort,
    );

    // Start the API server
    await _apiController!.start();

    // Set up auto team assignment callback
    networkCoordinator.setOnNodeJoinedCallback((nodeId, nodeName) {
      _headlessService!.handleNodeJoined(networkCoordinator, nodeId, nodeName);
    });

    // Schedule auto-start if configured
    _headlessService!.scheduleAutoStart(
      networkCoordinator,
      configureAndStartGame,
    );

    appLog.info('Headless features fully configured');
  }

  Future<void> _initializeCoordination() async {
    try {
      await initSettings();

      appLog.info('Starting coordination initialization...');
      // Check if we're in headless mode BEFORE initializing coordinator
      if (widget.headlessMode) {
        _headlessService = HeadlessConfigService.instance;
        await _headlessService!.initialize();

        // If headless mode, set coordinator as non-player BEFORE initialization
        if (_headlessService!.isHeadlessMode) {
          networkCoordinator.coordinatorAsPlayer = false;

          appLog.info('Headless mode: Coordinator will not be a player');
        }
      }

      await networkCoordinator.initialize();
      appLog.info('Coordination initialization completed successfully');

      // Create action provider but don't configure game yet
      // Game will be configured when user starts a game from menu
      _actionProvider = NetworkActionProvider(networkCoordinator);

      // If headless coordinator, update the action provider
      if (_headlessService?.isHeadlessMode ?? false) {
        if (_actionProvider is LocalActionProvider) {
          (_actionProvider as LocalActionProvider).headlessCoordinator = true;
        }
      }

      // Set up callback for when game actually starts (coordinated)
      networkCoordinator.setOnGameStartCallback(_onGameActuallyStarted);

      // NOW we can set up headless-specific features after coordinator is ready
      if ((_headlessService?.isHeadlessMode ?? false)) {
        await _setupHeadlessFeatures();
      }
      appLog.info('Action provider created and ready');
    } catch (error) {
      appLog.severe('Failed to initialize coordination: $error');
      // Fall back to local action provider
      _actionProvider = LocalActionProvider(_actionManager);
      appLog.warning('Using local action provider as fallback');
    }
  }

  /// Configure and start game (called from menu)
  Future<void> configureAndStartGame() async {
    if (_actionProvider == null) {
      appLog.warning('Action provider not ready, using local provider');
      _actionProvider = LocalActionProvider(_actionManager);
      // If headless, set the local provider as headless too
      if (_headlessService?.isHeadlessMode ?? false) {
        (_actionProvider as LocalActionProvider).headlessCoordinator = true;
      }
    }

    try {
      await game.configure(_actionProvider!);
      appLog.info('Game configured with action provider');

      // Configure the action provider for all nodes
      await _actionProvider!.startGameplay();

      // Only configure action provider for gameplay if not headless coordinator
      if (!(_headlessService?.isHeadlessMode ?? false) ||
          !networkCoordinator.isCoordinator) {
        await _actionProvider!.startGameplay();
      } else {
        // Headless coordinator just starts the game coordination
        await networkCoordinator.startGame();
      }

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
        _actionProvider = LocalActionProvider(_actionManager);
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

    if (_headlessService?.isHeadlessMode ?? false) {
      appLog.info('Headless mode: Skipping UI transitions');
      return;
    }

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
    game.resumeGame();
    appLog.info('Game engine started');
  }

  /// Log app data (high-frequency data that bypasses console)
  void logAppData(String event, Map<String, dynamic> data) {
    appLog.logData('app_data', event, data: data);
  }

  @override
  void dispose() {
    _apiController?.dispose();
    _headlessService?.dispose();
    _actionProvider?.dispose();
    _actionManager.dispose();
    networkCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // In headless mode, return minimal UI
    if (_headlessService?.isHeadlessMode ?? false) {
      return CupertinoApp(
        home: Container(
          color: CupertinoColors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'RiseTogether Server',
                  style: TextStyle(color: CupertinoColors.white, fontSize: 24),
                ),
                SizedBox(height: 20),
                Text(
                  'Running in headless mode',
                  style: TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 16,
                  ),
                ),
                if (_apiController != null) ...[
                  SizedBox(height: 10),
                  Text(
                    'API: http://localhost:${_headlessService!.config.httpApiPort}',
                    style: TextStyle(
                      color: CupertinoColors.systemGreen,
                      fontSize: 14,
                    ),
                  ),
                ],
                Offstage(
                  offstage: true,
                  child: SizedBox(
                    width: 100,
                    height: 200,
                    child: GameWidget(game: game),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize enhanced logging system and ensure it's complete before continuing
  final logService = LogService();
  await logService.initializeCompleteLogging(
    appLogDestination: LogDestination.both, // Console + File for app logs
    dataLoggers: ['app_data'], // File only for app data
    dataLogFormat: 'tsv',
  );

  // Double-check that initialization is complete
  await logService.ensureInitialized();

  // Debug: Print logging status
  final status = logService.getLoggingStatus();
  debugPrint('DEBUG - Logging status: $status');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  RiseTogetherPackageInfo().init(packageInfo);

  const appMode = String.fromEnvironment('APP_MODE', defaultValue: '');
  final isHeadless =
      appMode == 'headless_server' ||
      Platform.environment['RISETOGETHER_MODE'] == 'headless_server';

  runApp(
    ExcludeSemantics(
      child: EasyLocalization(
        supportedLocales: [Locale('en'), Locale('da')],
        path: 'assets/translations',
        fallbackLocale: Locale('en'),
        startLocale: Locale('da'),
        useOnlyLangCode: true,
        useFallbackTranslations: true,
        child: RiseTogetherApp(headlessMode: isHeadless),
      ),
    ),
  );
}
