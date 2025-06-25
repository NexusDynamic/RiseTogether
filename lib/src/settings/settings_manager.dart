import 'dart:async';
import 'settings_group.dart';
import 'exceptions.dart';

/// Global settings manager providing centralized access to all setting groups.
///
/// The [Settings] class serves as the main entry point for the settings framework,
/// offering static methods for registration, initialization, and access to settings
/// across your entire application. It manages multiple [SettingsGroup] instances and
/// provides both individual and batch operations.
///
/// ## Overview
///
/// The settings framework follows a hierarchical structure:
/// ```
/// Settings (Global Manager)
/// │
/// ├── SettingsGroup (Group: "game")
/// │   ├── BoolSetting ("soundEnabled")
/// │   └── DoubleSetting ("volume")
/// │
/// └── SettingsGroup (Group: "ui")
///     ├── StringSetting ("theme")
///     └── IntSetting ("fontSize")
/// ```
///
/// ## Usage Pattern
///
/// ```dart
/// // 1. Define your setting groups
/// final gameSettings = SettingsGroup(
///   key: 'game',
///   items: [
///     BoolSetting(key: 'soundEnabled', defaultValue: true),
///     DoubleSetting(key: 'volume', defaultValue: 0.8),
///   ],
/// );
///
/// final uiSettings = SettingsGroup(
///   key: 'ui',
///   items: [
///     StringSetting(key: 'theme', defaultValue: 'light'),
///     IntSetting(key: 'fontSize', defaultValue: 14),
///   ],
/// );
///
/// // 2. Register all groups
/// Settings.register(gameSettings);
/// Settings.register(uiSettings);
///
/// // 3. Initialize the entire settings system
/// await Settings.init();
///
/// // 4. Access settings using dot notation
/// bool soundEnabled = Settings.getBool('game.soundEnabled');
/// String theme = Settings.getString('ui.theme');
///
/// // 5. Modify settings with automatic validation
/// await Settings.setBool('game.soundEnabled', false);
/// await Settings.setString('ui.theme', 'dark');
///
/// // 6. Batch operations for efficiency
/// await Settings.setMultiple({
///   'game.volume': 0.5,
///   'ui.fontSize': 16,
/// });
///
/// // 7. Reset operations
/// await Settings.resetSetting('game.volume'); // Reset single setting
/// await Settings.resetGroup('ui');            // Reset entire group
/// await Settings.resetAll();                  // Reset everything
/// ```
///
/// ## Storage Key Format
///
/// Settings are stored using a namespaced key format: `groupKey.settingKey`
/// - `game.soundEnabled` → boolean setting in the game group
/// - `ui.theme` → string setting in the ui group
/// - `network.timeout` → integer setting in the network group
///
/// This prevents key conflicts between different setting groups and provides
/// logical organization of related settings.
class Settings {
  /// Internal registry of all settings groups keyed by their group names.
  ///
  /// This map stores all registered [SettingsGroup] instances, providing
  /// fast lookup by group key. Groups must be registered before use.
  static final Map<String, SettingsGroup> _settings = {};

  /// Initializes all registered settings groups concurrently.
  ///
  /// This method waits for all registered settings groups to complete their
  /// asynchronous initialization. It's essential to call this method before
  /// accessing any setting values to ensure they've been loaded from storage.
  ///
  /// The initialization process:
  /// 1. Waits for the underlying SharedPreferences to be ready
  /// 2. Loads existing values from storage for each setting
  /// 3. Creates default values for settings that don't exist yet
  /// 4. Marks all groups as ready for synchronous access
  ///
  /// Returns: Future that completes when all settings are initialized
  ///
  /// Throws: Exception if any settings group fails to initialize
  ///
  /// Example:
  /// ```dart
  /// // Register your settings groups first
  /// Settings.register(gameSettings);
  /// Settings.register(uiSettings);
  ///
  /// // Then initialize everything
  /// await Settings.init();
  ///
  /// // Now safe to use settings synchronously
  /// bool soundEnabled = Settings.getBool('game.soundEnabled');
  /// ```
  Future<void> init() async {
    final futures = _settings.values.map((settings) => settings.readyFuture);
    await Future.wait(futures);
  }

  /// Returns a map of all registered settings groups.
  Map<String, SettingsGroup> get groups => _settings;

  /// Returns a list of all registered settings groups keys.
  List<String> get groupKeys => _settings.keys.toList();

  /// Allow access to settings by key using dynamic getters.
  /// This allows you to access settings like:
  /// Settings.game.fullscreen, Settings.game.soundVolume, etc.
  @override
  SettingsGroup noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      final key = invocation.memberName.toString();
      if (_settings.containsKey(key)) {
        return _settings[key]!;
      }
    }
    throw NoSuchMethodError.withInvocation(this, invocation);
  }

  /// Validate and get the parts of a storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid.
  static ({String group, String setting}) _parseStorageKey(String storageKey) {
    final parts = storageKey.split('.');
    if (parts.length < 2) {
      throw ArgumentError('Invalid storage key: $storageKey');
    }
    return (group: parts.first, setting: parts.sublist(1).join('.'));
  }

  // ===== Getters =====

  /// Override the accessor to allow dynamic access to settings
  /// using the `[]` operator.
  dynamic operator [](String key) {
    return get<dynamic>(key);
  }

  /// Registers a settings group with the global settings manager.
  ///
  /// Each settings group must be registered before the system can be initialized.
  /// Groups are identified by their unique key, and duplicate keys are not allowed.
  ///
  /// This method should be called during application startup, before calling [init].
  ///
  /// Parameters:
  /// - [settings]: The SettingsGroup instance to register
  ///
  /// Throws: [ArgumentError] if a group with the same key already exists
  ///
  /// Example:
  /// ```dart
  /// final gameSettings = SettingsGroup(key: 'game', items: [...]);
  /// final uiSettings = SettingsGroup(key: 'ui', items: [...]);
  ///
  /// Settings.register(gameSettings);
  /// Settings.register(uiSettings);
  ///
  /// await Settings.init(); // Initialize after all groups are registered
  /// ```
  void register(SettingsGroup settings) {
    if (_settings.containsKey(settings.key)) {
      throw ArgumentError('Settings with key ${settings.key} already exists');
    }
    _settings[settings.key] = settings;
  }

  /// Gets a settings group by its key.
  SettingsGroup getGroup(String key) {
    if (!_settings.containsKey(key)) {
      throw SettingNotFoundException('No settings group found for key: $key');
    }
    return _settings[key]!;
  }

  /// Get a setting by its storage key and type.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found.
  T get<T>(String storageKey) {
    // Split the storage key to get the group key and setting key.
    final id = _parseStorageKey(storageKey);

    final group = getGroup(id.group);
    return group.get<T>(id.setting);
  }

  // Helpers for typed access to settings.
  // These methods are for convenience to access settings without
  // ending up with a dynamic value.

  /// Gets a boolean setting by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not of type bool.
  bool getBool(String storageKey) {
    return get<bool>(storageKey);
  }

  /// Gets a double setting by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not of type int.
  int getInt(String storageKey) {
    return get<int>(storageKey);
  }

  /// Gets a double setting by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not of type double.
  double getDouble(String storageKey) {
    return get<double>(storageKey);
  }

  /// Gets a string setting by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not of type string.
  String getString(String storageKey) {
    return get<String>(storageKey);
  }

  // ===== Setters =====

  /// Sets a setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  Future<void> setValue(String storageKey, dynamic value) async {
    final id = _parseStorageKey(storageKey);
    final group = getGroup(id.group);
    await group.setValue(id.setting, value);
  }

  /// Sets a setting value by its storage key and type.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  Future<void> set<T>(String storageKey, T value) async {
    final id = _parseStorageKey(storageKey);
    final group = getGroup(id.group);
    await group.setValue<T>(id.setting, value);
  }

  /// Sets a boolean setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  Future<void> setBool(String storageKey, bool value) async {
    await set<bool>(storageKey, value);
  }

  /// Sets an integer setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  Future<void> setInt(String storageKey, int value) async {
    await set<int>(storageKey, value);
  }

  /// Sets a double setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  Future<void> setDouble(String storageKey, double value) async {
    await set<double>(storageKey, value);
  }

  /// Sets a string setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  Future<void> setString(String storageKey, String value) async {
    await set<String>(storageKey, value);
  }

  /// Sets multiple settings values in a batch operation.
  /// The [settings] map should contain storage keys as keys and values as values.
  /// This is more efficient than setting values individually.
  Future<void> setMultiple(Map<String, dynamic> settings) async {
    final futures = <Future<void>>[];
    for (final entry in settings.entries) {
      futures.add(setValue(entry.key, entry.value));
    }
    await Future.wait(futures);
  }

  /// Reset a setting to its default value by storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  Future<void> resetSetting(String storageKey) async {
    final id = _parseStorageKey(storageKey);
    final group = getGroup(id.group);
    await group.reset(id.setting);
  }

  /// Reset all settings in a group to their default values.
  /// The [groupKey] should be the key of the settings group.
  Future<void> resetGroup(String groupKey) async {
    final group = getGroup(groupKey);
    await group.resetAll();
  }

  /// Reset all settings across all groups to their default values.
  Future<void> resetAll() async {
    final futures = _settings.values.map((group) => group.resetAll());
    await Future.wait(futures);
  }

  /// Dispose all settings groups and their stream controllers.
  void dispose() {
    for (final group in _settings.values) {
      group.dispose();
    }
    _settings.clear();
  }

  /// Clear all registered settings groups (for testing purposes).
  void clearAll() {
    dispose();
  }

  @override
  String toString() {
    return 'Settings{groups: ${_settings.keys.join(', ')}}';
  }
}
