/// =============================================================================
/// MODULAR SETTINGS FRAMEWORK
/// =============================================================================
///
/// A comprehensive, type-safe settings management framework for Flutter/Dart
/// applications.
///
/// Usage Example:
/// ```dart
/// // Define your settings
/// final gameSettings = SettingsBase(
///   key: 'game',
///   items: SettingsGroup(items: [
///     BoolSetting(key: 'soundEnabled', defaultValue: true),
///     DoubleSetting(
///       key: 'volume',
///       defaultValue: 0.8,
///       validator: (v) => v >= 0.0 && v <= 1.0,
///     ),
///   ]),
/// );
///
/// // Register and initialize
/// Settings.register(gameSettings);
/// await Settings.init();
///
/// // Use settings
/// bool sound = Settings.getBool('game.soundEnabled');
/// await Settings.setBool('game.soundEnabled', false);
///
/// // Listen for changes
/// gameSettings.items['soundEnabled']!.stream.listen((value) {
///   print('Sound enabled changed to: $value');
/// });
/// ```
///
/// =============================================================================
library;

export 'settings_common.dart';
export 'game.dart';
