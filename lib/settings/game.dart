import 'settings_common.dart';

/// Game settings group containing all game-related preferences.
/// 
/// Example usage:
/// ```dart
/// Settings.register(gameSettings);
/// await Settings.init();
/// 
/// bool soundEnabled = gameSettings.get<bool>('enable_sound');
/// await gameSettings.setValue('enable_sound', false);
/// ```
final gameSettings = SettingsGroup(
  key: 'game_settings',
  items: [
    BoolSetting(key: 'enable_sound', defaultValue: true),
  ],
);
