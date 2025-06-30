import 'setting.dart';
import 'settings_group.dart';

/// Game settings group containing all game-related preferences.
final gameSettings = SettingsGroup(
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
  ],
);
