import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/network_coordinator.dart';
import 'package:rise_together/src/settings/app_settings.dart';

/// Configuration for headless server mode
class HeadlessConfig {
  final bool autoStart;
  final int autoStartDelay;
  final bool skipSurveys;
  final bool autoProgressLevels;
  final int levelTransitionDelay;
  final Map<String, dynamic> gameSettings;
  final Map<String, dynamic> physicsSettings;
  final List<TeamAssignmentRule>? teamAssignmentRules;
  final int? httpApiPort;

  HeadlessConfig({
    this.autoStart = true,
    this.autoStartDelay = 10,
    this.skipSurveys = true,
    this.autoProgressLevels = true,
    this.levelTransitionDelay = 5,
    this.gameSettings = const {},
    this.physicsSettings = const {},
    this.teamAssignmentRules,
    this.httpApiPort,
  });

  factory HeadlessConfig.fromJson(Map<String, dynamic> json) {
    return HeadlessConfig(
      autoStart: json['autoStart'] ?? true,
      autoStartDelay: json['autoStartDelay'] ?? 10,
      skipSurveys: json['skipSurveys'] ?? true,
      autoProgressLevels: json['autoProgressLevels'] ?? true,
      levelTransitionDelay: json['levelTransitionDelay'] ?? 5,
      gameSettings: json['gameSettings'] ?? {},
      physicsSettings: json['physicsSettings'] ?? {},
      teamAssignmentRules: json['teamAssignmentRules'] != null
          ? (json['teamAssignmentRules'] as List)
                .map((r) => TeamAssignmentRule.fromJson(r))
                .toList()
          : null,
      httpApiPort: json['httpApiPort'],
    );
  }

  Map<String, dynamic> toJson() => {
    'autoStart': autoStart,
    'autoStartDelay': autoStartDelay,
    'skipSurveys': skipSurveys,
    'autoProgressLevels': autoProgressLevels,
    'levelTransitionDelay': levelTransitionDelay,
    'gameSettings': gameSettings,
    'physicsSettings': physicsSettings,
    'teamAssignmentRules': teamAssignmentRules?.map((r) => r.toJson()).toList(),
    'httpApiPort': httpApiPort,
  };
}

/// Rule for automatic team assignment
class TeamAssignmentRule {
  final String pattern; // Regex pattern for node name/id
  final int teamId;
  final int? maxPlayers;

  TeamAssignmentRule({
    required this.pattern,
    required this.teamId,
    this.maxPlayers,
  });

  factory TeamAssignmentRule.fromJson(Map<String, dynamic> json) {
    return TeamAssignmentRule(
      pattern: json['pattern'],
      teamId: json['teamId'],
      maxPlayers: json['maxPlayers'],
    );
  }

  Map<String, dynamic> toJson() => {
    'pattern': pattern,
    'teamId': teamId,
    'maxPlayers': maxPlayers,
  };
}

/// Service for managing headless server configuration
class HeadlessConfigService with AppLogging, AppSettings {
  static HeadlessConfigService? _instance;
  static HeadlessConfigService get instance {
    _instance ??= HeadlessConfigService._();
    return _instance!;
  }

  HeadlessConfig? _config;
  HeadlessConfig get config => _config ?? HeadlessConfig();

  bool _isHeadlessMode = false;
  bool get isHeadlessMode => _isHeadlessMode;

  Timer? _autoStartTimer;
  Timer? _levelTransitionTimer;

  HeadlessConfigService._();

  /// Initialize the service and detect headless mode
  Future<void> initialize() async {
    // Check if running in headless mode via environment or dart define
    _isHeadlessMode = _checkHeadlessMode();

    if (!_isHeadlessMode) {
      appLog.info('Running in normal mode');
      return;
    }

    appLog.info('Running in HEADLESS SERVER mode');

    // Load configuration
    await _loadConfiguration();

    // Apply settings
    await _applyConfiguration();
  }

  bool _checkHeadlessMode() {
    // Check dart define
    const appMode = String.fromEnvironment('APP_MODE', defaultValue: '');
    if (appMode == 'headless_server') return true;

    // Check environment variable
    final envMode = Platform.environment['RISETOGETHER_MODE'];
    if (envMode == 'headless_server') return true;

    // Check for presence of config file
    final configFile = File('risetogether_config.json');
    if (configFile.existsSync()) {
      appLog.info('Config file found, enabling headless mode');
      return true;
    }

    return false;
  }

  Future<void> _loadConfiguration() async {
    try {
      // Try loading from file first
      final configFilePath =
          Platform.environment['RISETOGETHER_CONFIG_FILE'] ??
          String.fromEnvironment(
            'APP_CONFIG_FILE',
            defaultValue: 'risetogether_config.json',
          );
      final configFile = File(configFilePath);
      appLog.info('Attempting to load configuration from $configFilePath');
      if (configFile.existsSync()) {
        try {
          final jsonStr = await configFile.readAsString();
          final json = jsonDecode(jsonStr);
          _config = HeadlessConfig.fromJson(json);
          appLog.info('Loaded configuration from $configFilePath');
          return;
        } catch (e) {
          appLog.severe('Failed to parse configuration file: $e');
        }
      } else {
        appLog.warning('Configuration file not found at $configFilePath');
      }

      // Try environment variable
      final envConfig = Platform.environment['RISETOGETHER_CONFIG'];
      if (envConfig != null) {
        final json = jsonDecode(envConfig);
        _config = HeadlessConfig.fromJson(json);
        appLog.info('Loaded configuration from environment variable');
        return;
      }

      // Use default config
      _config = HeadlessConfig();
      appLog.info('Using default headless configuration');
    } catch (e) {
      appLog.severe('Failed to load headless configuration: $e');
      _config = HeadlessConfig();
    }
  }

  Future<void> _applyConfiguration() async {
    if (_config == null) return;

    try {
      // Apply game settings
      for (final entry in _config!.gameSettings.entries) {
        final key = 'game.${entry.key}';
        if (entry.value is bool) {
          await appSettings.setBool(key, entry.value);
        } else if (entry.value is int) {
          await appSettings.setInt(key, entry.value);
        } else if (entry.value is double) {
          await appSettings.setDouble(key, entry.value);
        }
      }

      // Apply physics settings
      for (final entry in _config!.physicsSettings.entries) {
        final key = 'physics.${entry.key}';
        if (entry.value is double) {
          await appSettings.setDouble(key, entry.value);
        }
      }

      // Force skip surveys in headless mode
      await appSettings.setBool('game.enable_surveys', false);

      appLog.info('Applied headless configuration to app settings');
    } catch (e) {
      appLog.severe('Failed to apply configuration: $e');
    }
  }

  /// Schedule auto-start of the game
  void scheduleAutoStart(
    NetworkCoordinator coordinator,
    Function() startGameCallback,
  ) {
    if (!_isHeadlessMode || !_config!.autoStart) return;

    appLog.info('Scheduling auto-start in ${_config!.autoStartDelay} seconds');

    _autoStartTimer?.cancel();
    _autoStartTimer = Timer(Duration(seconds: _config!.autoStartDelay), () {
      if (coordinator.canStartGame()) {
        appLog.info('Auto-starting game');
        startGameCallback();
      } else {
        appLog.warning('Cannot auto-start: no players assigned');
        // Retry in a few seconds
        scheduleAutoStart(coordinator, startGameCallback);
      }
    });
  }

  /// Handle automatic team assignment for new nodes
  void handleNodeJoined(
    NetworkCoordinator coordinator,
    String nodeId,
    String nodeName,
  ) {
    if (!_isHeadlessMode || _config!.teamAssignmentRules == null) return;

    // Don't assign the coordinator itself
    if (nodeId == coordinator.deviceUId) {
      appLog.info('Skipping assignment for coordinator node in headless mode');
      return;
    }

    for (final rule in _config!.teamAssignmentRules!) {
      final regex = RegExp(rule.pattern);
      if (regex.hasMatch(nodeName) || regex.hasMatch(nodeId)) {
        // Special case: teamId -1 means auto-balance
        if (rule.teamId == -1) {
          _autoBalanceTeam(coordinator, nodeId, nodeName);
          return;
        }

        // Check max players limit
        if (rule.maxPlayers != null) {
          final currentCount = coordinator.playerAssignments
              .where((a) => a.teamId == rule.teamId && !a.isCoordinator)
              .length;
          if (currentCount >= rule.maxPlayers!) {
            continue;
          }
        }

        appLog.info(
          'Auto-assigning node $nodeName to team ${rule.teamId} based on rule',
        );
        coordinator.assignNodeToTeam(nodeId, rule.teamId);
        return;
      }
    }

    // Default: balance teams
    _autoBalanceTeam(coordinator, nodeId, nodeName);
  }

  void _autoBalanceTeam(
    NetworkCoordinator coordinator,
    String nodeId,
    String nodeName,
  ) {
    final teamCounts = <int, int>{0: 0, 1: 0};

    // Count only non-coordinator players
    for (final assignment in coordinator.playerAssignments) {
      if (!assignment.isCoordinator) {
        teamCounts[assignment.teamId] =
            (teamCounts[assignment.teamId] ?? 0) + 1;
      }
    }

    final teamId = (teamCounts[0]! <= teamCounts[1]!) ? 0 : 1;

    appLog.info(
      'Auto-balancing: Assigning node $nodeName to team $teamId (Team 0: ${teamCounts[0]}, Team 1: ${teamCounts[1]})',
    );
    coordinator.assignNodeToTeam(nodeId, teamId);
  }

  /// Schedule automatic level progression
  void scheduleLevelTransition(Function() callback) {
    if (!_isHeadlessMode || !_config!.autoProgressLevels) return;

    appLog.info(
      'Scheduling level transition in ${_config!.levelTransitionDelay} seconds',
    );

    _levelTransitionTimer?.cancel();
    _levelTransitionTimer = Timer(
      Duration(seconds: _config!.levelTransitionDelay),
      () {
        appLog.info('Auto-progressing to next level');
        callback();
      },
    );
  }

  /// Cancel all scheduled timers
  void cancelTimers() {
    _autoStartTimer?.cancel();
    _levelTransitionTimer?.cancel();
  }

  void dispose() {
    cancelTimers();
  }
}
