import 'setting.dart';
import 'settings_group.dart';
import 'settings_manager.dart';

/// Game settings group containing all game-related preferences.
final gameSettings = SettingsGroup(
  key: 'game',
  items: [BoolSetting(key: 'enable_sound', defaultValue: true)],
);

// ignore: unused_element
final _r = Settings.register(gameSettings);
