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
  ],
);
