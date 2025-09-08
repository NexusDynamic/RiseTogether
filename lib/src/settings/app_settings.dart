import 'package:synchronized/synchronized.dart';
import 'package:easy_shared_preferences/easy_shared_preferences.dart';

mixin class AppSettings {
  EasySettings get appSettings => GlobalSettings.instance;
  static bool _isInitialized = false;
  static final _lock = Lock();

  Future<void> initSettings() async {
    await _lock.synchronized(() async {
      if (_isInitialized) return;
      _isInitialized = true;

      await GlobalSettings.initialize([
        // Game settings group
        GroupConfig(
          key: 'game',
          items: [
            /// This defines the relative size of the game's maps.
            /// If the scale is 1.0, that means 1 "game unit" is 1 meter. This should
            /// be a very small value, to avoid floating point precision issues.
            DoubleSetting(key: 'game_scale', defaultValue: 0.0001),
            DoubleSetting(key: 'ball_radius', defaultValue: 1.0),

            /// Debug mode to show simulated player controls
            BoolSetting(key: 'debug_mode', defaultValue: true),

            /// Level duration in seconds
            DoubleSetting(key: 'level_duration', defaultValue: 120.0),

            /// Distance multiplier for converting game units to meters
            DoubleSetting(key: 'distance_multiplier', defaultValue: 100.0),

            /// Number of rounds in a tournament
            IntSetting(key: 'tournament_rounds', defaultValue: 3),

            /// Number of levels per round
            IntSetting(key: 'levels_per_round', defaultValue: 5),

            /// Enable surveys between levels
            BoolSetting(key: 'enable_surveys', defaultValue: false),

            /// Enable simulated player mode for demo/presentation
            BoolSetting(key: 'simulated_players', defaultValue: false),

            /// Enable local-only mode (no network communication)
            BoolSetting(key: 'local_only_mode', defaultValue: false),
          ],
        ),
        // Physics settings group
        GroupConfig(
          key: 'physics',
          items: [
            DoubleSetting(key: 'gravity', defaultValue: 9.81),
            DoubleSetting(key: 'paddle_width_multiplier', defaultValue: 1.0),
          ],
        ),
        // Color settings group
        GroupConfig(
          key: 'colors',
          items: [
            /// Base color for Team A
            IntSetting(
              key: 'team_a_color',
              defaultValue: 0xFF007AFF,
            ), // CupertinoColors.systemBlue
            /// Base color for Team B
            IntSetting(
              key: 'team_b_color',
              defaultValue: 0xFFFF9500,
            ), // CupertinoColors.systemOrange
          ],
        ),
        GroupConfig(
          key: 'device',
          items: [
            /// Persistent device ID for network coordination
            StringSetting(key: 'device_id', defaultValue: ''),

            /// Human-readable device name for network coordination
            StringSetting(key: 'device_name', defaultValue: ''),

            StringSetting(key: 'device_uid', defaultValue: ''),
          ],
        ),
        GroupConfig(
          key: 'network',
          items: [
            /// Whether to use local network mode (true) or network coordination (false)
            BoolSetting(key: 'use_local_network', defaultValue: false),

            /// Network timeout for coordination operations in seconds
            DoubleSetting(key: 'coordination_timeout', defaultValue: 10.0),

            /// Performance preset for network communication
            StringSetting(key: 'performance_preset', defaultValue: 'balanced'),
          ],
        ),
      ]);
    });
  }
}
