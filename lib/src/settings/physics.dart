import 'setting.dart';
import 'settings_group.dart';

/// Game settings group containing all physics configuration.
final physicsSettings = SettingsGroup(
  key: 'physics',
  items: [DoubleSetting(key: 'gravity', defaultValue: 9.81)],
);
