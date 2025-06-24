import 'setting.dart';
import 'settings_group.dart';
import 'settings_manager.dart';

/// Game settings group containing all physics configuration.
final physicsSettings = SettingsGroup(
  key: 'physics',
  items: [DoubleSetting(key: 'gravity', defaultValue: 9.81)],
);

// ignore: unused_element
final _r = Settings.register(physicsSettings);
