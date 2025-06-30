import 'setting.dart';
import 'settings_group.dart';

/// Color settings group containing team color preferences.
final colorSettings = SettingsGroup(
  key: 'colors',
  items: [
    /// Base color for Team A
    IntSetting(key: 'team_a_color', defaultValue: 0xFF007AFF), // CupertinoColors.systemBlue
    /// Base color for Team B  
    IntSetting(key: 'team_b_color', defaultValue: 0xFFFF9500), // CupertinoColors.systemOrange
  ],
);