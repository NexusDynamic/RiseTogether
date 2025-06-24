import 'dart:async';
import 'dart:collection';

import 'exceptions.dart';
import 'settings_store.dart';
import 'setting.dart';

/// A comprehensive settings group that manages related settings with persistence,
/// initialization, and type-safe access.
///
/// [SettingsGroup] extends [UnmodifiableMapBase] to provide convenient
/// map-like access to settings while managing their persistence and validation.
/// Each group has a unique key namespace and handles its own initialization.
///
/// Usage pattern:
/// ```dart
/// // 1. Define your settings group
/// final gameSettings = SettingsGroup(
///   key: 'game',
///   items: [
///     BoolSetting(key: 'soundEnabled', defaultValue: true),
///     DoubleSetting(key: 'volume', defaultValue: 0.8),
///   ],
/// );
///
/// // 2. Register with the global settings manager
/// Settings.register(gameSettings);
///
/// // 3. Wait for initialization
/// await gameSettings.readyFuture;
///
/// // 4. Use the settings
/// bool soundEnabled = gameSettings.get<bool>('soundEnabled');
/// await gameSettings.setValue('volume', 0.5);
/// ```
class SettingsGroup extends UnmodifiableMapBase<String, Setting> {
  /// Reference to the singleton settings store for persistence.
  ///
  /// This store handles the actual reading and writing of values
  /// to SharedPreferences with caching for performance.
  late final SettingsStore _store;

  /// Unique identifier for this settings group.
  ///
  /// This key is used as a namespace prefix for all settings in this group.
  /// For example, if key is 'game' and a setting key is 'volume',
  /// the stored key becomes 'game.volume'.
  ///
  /// Should be descriptive and unique across your application.
  final String key;

  /// Immutable set of all settings contained in this group.
  ///
  /// This set is created during construction and cannot be modified afterward.
  /// It contains all the setting objects that belong to this group.
  late final Set<Setting<dynamic>> items;

  /// Internal cache of setting keys for efficient lookups.
  ///
  /// This set contains the string keys of all settings in the group,
  /// providing O(1) key existence checks and fast iteration.
  late final Set<String> _keys;

  /// Internal flag tracking initialization status.
  bool _ready = false;

  /// Public property indicating whether this settings group is ready for use.
  ///
  /// When false, accessing setting values will throw [SettingsNotReadyException].
  /// When true, all settings have been loaded and are available synchronously.
  bool get ready => _ready;

  /// Internal completer that completes when initialization finishes.
  late Completer<bool> _readyCompleter;

  /// Future that completes when all settings in this group are initialized.
  ///
  /// Await this future before accessing setting values to ensure they've
  /// been loaded from storage. The future completes with true on success
  /// or throws an exception if initialization fails.
  ///
  /// Example:
  /// ```dart
  /// await gameSettings.readyFuture;
  /// // Now safe to access settings synchronously
  /// bool soundEnabled = gameSettings.get<bool>('soundEnabled');
  /// ```
  Future<bool> get readyFuture => _readyCompleter.future;

  /// Creates a new settings group with the given key and settings.
  ///
  /// The provided [items] are converted to an immutable set, and their
  /// keys are extracted for efficient access. Duplicate keys within
  /// the same group are not allowed and will cause undefined behavior.
  ///
  /// Parameters:
  /// - [key]: Unique identifier for this settings group
  /// - [items]: Collection of settings to include in this group
  /// - [forceRegularSharedPreferences]: Whether to force regular SharedPreferences (for testing)
  ///
  /// Example:
  /// ```dart
  /// final group = SettingsGroup(
  ///   key: 'game',
  ///   items: [
  ///     BoolSetting(key: 'notifications', defaultValue: true),
  ///     IntSetting(key: 'timeout', defaultValue: 30),
  ///   ],
  /// );
  /// ```
  SettingsGroup({
    required this.key,
    required Iterable<Setting> items,
    bool forceRegularSharedPreferences = false,
  }) {
    this.items = Set<Setting>.from(items);
    _keys = items.map((item) => item.key).toSet();
    _store = SettingsStore(
      forceRegularSharedPreferences: forceRegularSharedPreferences,
    );
    _readyCompleter = Completer<bool>();
    // Initialize the settings in the storage if they haven't been set yet.
    _init();
  }

  /// Creates a new settings group optimized for testing.
  /// This constructor forces the use of regular SharedPreferences instead
  /// of SharedPreferencesWithCache to avoid test compatibility issues.
  SettingsGroup.forTesting({
    required this.key,
    required Iterable<Setting> items,
  }) {
    this.items = Set<Setting>.from(items);
    _keys = items.map((item) => item.key).toSet();
    _store = SettingsStore(forceRegularSharedPreferences: true);
    _readyCompleter = Completer<bool>();
    // Initialize the settings in the storage if they haven't been set yet.
    _init();
  }

  /// Retrieves a setting by its key.
  ///
  /// This operator provides map-like access to settings within the group.
  /// The return type is [Setting<dynamic>] to accommodate different setting types.
  ///
  /// Parameters:
  /// - [key]: The string key of the setting to retrieve
  ///
  /// Returns: The setting object with the specified key or null if not found.
  ///
  /// Example:
  /// ```dart
  /// Setting volumeSetting = audioGroup['volume'];
  /// BoolSetting enabledSetting = audioGroup['enabled'] as BoolSetting;
  /// ```
  @override
  Setting<dynamic>? operator [](Object? key) {
    try {
      return items.firstWhere((item) => item.key == key);
    } catch (_) {
      return null;
    }
  }

  /// Returns an iterable of all setting keys in this group.
  ///
  /// This property provides the keys needed for map-like iteration
  /// and key existence checking.
  ///
  /// Returns: Iterable containing all setting keys as strings
  @override
  Iterable<String> get keys => _keys;

  /// Returns the number of settings in this group.
  ///
  /// This count includes all settings regardless of their type
  /// or configurability status.
  ///
  /// Returns: Integer count of settings in the group
  @override
  int get length => _keys.length;

  /// Initializes the settings by checking if they are set in the storage.
  /// If not, it sets them with their default values.
  /// This is called in the constructor to ensure settings are ready to use.
  /// It waits for the store to be ready before proceeding, but there is no
  /// guarantee that the settings are initialized before the first access.
  /// If you need to ensure settings are initialized before use, you should
  /// await the [readyFuture] before accessing any settings.
  Future<void> _init() async {
    try {
      if (!_store.ready) {
        await _store.readyFuture;
      }
      for (final Setting setting in items) {
        final storageKey = _storageKey(setting.key);
        if (!_store.prefs.containsKey(storageKey)) {
          // If the setting is not set, initialize it with the default value.
          await _set(storageKey, setting, null, force: true);
        } else {
          // Validate existing value and reset to default if invalid
          try {
            final currentValue = _get(setting);
            if (setting.validator != null && !setting.validate(currentValue)) {
              await _set(storageKey, setting, null, force: true);
            }
          } catch (e) {
            // If there's an error reading the current value, reset to default
            await _set(storageKey, setting, null, force: true);
          }
        }
      }
      _ready = true;
      _readyCompleter.complete(true);
    } catch (error) {
      _ready = false;
      _readyCompleter.completeError(error);
      rethrow;
    }
  }

  /// Sets the value of a setting by its key.
  Future<void> setValue<T>(String key, T value) async {
    await _waitUntilReady();
    final setting = this[key];
    if (setting == null) {
      throw SettingNotFoundException(
        'No setting in ${this.key} found for key: $key',
      );
    }
    final storageKey = _storageKey(setting.key);
    if (!setting.userConfigurable) {
      throw SettingNotConfigurableException(
        'Setting $storageKey is not user configurable',
      );
    }

    // Validate the value if a validator is provided
    if (setting is Setting<T> && !setting.validate(value)) {
      throw SettingValidationException(
        'Invalid value for setting $storageKey: $value',
      );
    }

    await _set(storageKey, setting, value);

    // Notify change listeners
    if (setting is Setting<T>) {
      setting.notifyChange(value);
    }
  }

  /// Convenience method to get a typed value of a setting by its key.
  /// Throws an error if the setting is not found or if the type does not match.
  T get<T>(String key) {
    _readySync();
    if (T == dynamic) {
      return getValue(key);
    }
    final setting = this[key];
    if (setting == null) {
      throw SettingNotFoundException(
        'No setting in ${this.key} found for key: $key',
      );
    }
    if (setting is! Setting<T>) {
      throw ArgumentError(
        'Setting $key is not of type ${T.runtimeType}, but ${setting.type}',
      );
    }

    return _get<T>(setting);
  }

  /// Gets the value of a setting by its key.
  dynamic getValue(String key) {
    _readySync();
    final setting = this[key];
    if (setting == null) {
      throw SettingNotFoundException(
        'No setting in ${this.key} found for key: $key',
      );
    }

    return _get(setting);
  }

  /// Ensures that the settings are ready before accessing them.
  /// Throws a [SettingsNotReadyException] if the settings are not ready.
  void _readySync() {
    if (!_ready) {
      throw SettingsNotReadyException(
        'Settings are not ready. Please await readyFuture.',
      );
    }
  }

  /// Waits until the settings are ready.
  /// This is useful for asynchronous operations that need to ensure
  /// settings are initialized.
  Future<void> _waitUntilReady() async {
    if (!_ready) {
      await _readyCompleter.future;
    }
  }

  /// Constructs a storage key for the given key in this settings group.
  /// This is used to namespace the settings keys to avoid conflicts.
  /// For example, if the group key is "game" and the setting key is
  /// "fullscreen", the storage key will be "game.fullscreen".
  String _storageKey(String key) {
    return "${this.key}.$key";
  }

  T _validateOrDefault<T>(Setting<T> setting, T? value) {
    if (value == null) return setting.defaultValue;
    if (setting.validator != null && !setting.validate(value)) {
      // return default value if validation fails
      return setting.defaultValue;
    }
    return value;
  }

  /// Gets the value of a setting by its key and type.
  /// Throws an error if the setting is not found or if the type does not match.
  /// This method is used internally to retrieve the value of a setting.
  T _get<T>(Setting<T> setting) {
    final storageKey = _storageKey(setting.key);
    if (!_store.prefs.containsKey(storageKey)) {
      // If not found in storage, return default value
      return setting.defaultValue;
    }

    try {
      switch (T) {
        case const (bool):
          final value = _store.prefs.getBool(storageKey);
          // validate the value if a validator is provided
          return _validateOrDefault(setting, value as T);
        case const (int):
          final value = _store.prefs.getInt(storageKey);
          return _validateOrDefault(setting, value as T);
        case const (double):
          final value = _store.prefs.getDouble(storageKey);
          return _validateOrDefault(setting, value as T);
        case const (String):
          final value = _store.prefs.getString(storageKey);
          return _validateOrDefault(setting, value as T);
        default:
          throw ArgumentError('Unsupported setting type: ${T.runtimeType}');
      }
    } catch (e) {
      // If there's a type mismatch or other error, return default value
      return setting.defaultValue;
    }
  }

  /// Sets the value of a setting by its key and type.
  /// Throws an error if the setting is not found or if the type does not match.
  /// This method is used internally to set the value of a setting.
  /// If [force] is true, it will set the value even if the setting is
  /// not user configurable.
  /// If [value] is null, it will use the default value of the setting.
  /// If the setting is not user configurable and [force] is false,
  /// it will throw an error.
  Future<void> _set<T>(
    String storageKey,
    Setting<T> setting,
    T? value, {
    bool force = false,
  }) async {
    if (!force && !setting.userConfigurable) {
      throw SettingNotConfigurableException(
        'Setting $storageKey is not user configurable',
      );
    }
    if (!force && !_store.prefs.containsKey(storageKey)) {
      throw SettingNotFoundException('No setting found for: $storageKey');
    }

    switch (T) {
      case const (bool):
        value ??= setting.defaultValue;
        return _setBool(storageKey, value as bool);
      case const (int):
        value ??= setting.defaultValue;
        return _setInt(storageKey, value as int);
      case const (double):
        value ??= setting.defaultValue;
        return _setDouble(storageKey, value as double);
      case const (String):
        value ??= setting.defaultValue;
        return _setString(storageKey, value as String);
      case const (dynamic):
        // If the type is dynamic, we can return any value.
        // This is a fallback for when the type is not known at compile time.
        // it is less efficient, but let's face it, you probably should not be
        // updating settings 1000s of times per second.
        value ??= setting.defaultValue;

        switch (setting.type) {
          case SettingType.bool:
            return _setBool(storageKey, value as bool);
          case SettingType.int:
            return _setInt(storageKey, value as int);
          case SettingType.double:
            return _setDouble(storageKey, value as double);
          case SettingType.string:
            return _setString(storageKey, value as String);
        }
      default:
        throw ArgumentError('Unsupported setting type: ${T.runtimeType}');
    }
  }

  /// Sets a boolean value for the given storage key.
  Future<void> _setBool(String storageKey, bool value) async {
    await _store.prefs.setBool(storageKey, value);
  }

  /// Sets an integer value for the given storage key.
  Future<void> _setInt(String storageKey, int value) async {
    await _store.prefs.setInt(storageKey, value);
  }

  /// Sets a double value for the given storage key.
  Future<void> _setDouble(String storageKey, double value) async {
    await _store.prefs.setDouble(storageKey, value);
  }

  /// Sets a string value for the given storage key.
  Future<void> _setString(String storageKey, String value) async {
    await _store.prefs.setString(storageKey, value);
  }

  /// Reset a setting to its default value.
  Future<void> reset(String key) async {
    await _waitUntilReady();
    final setting = this[key];
    if (setting == null) {
      throw SettingNotFoundException(
        'No setting in ${this.key} found for key: $key',
      );
    }
    final storageKey = _storageKey(setting.key);
    await _set(storageKey, setting, null, force: true);

    // Notify change listeners
    setting.notifyChange(setting.defaultValue);
  }

  /// Reset all settings in this group to their default values.
  Future<void> resetAll() async {
    await _waitUntilReady();
    for (final setting in items) {
      final storageKey = _storageKey(setting.key);
      await _set(storageKey, setting, null, force: true);
      setting.notifyChange(setting.defaultValue);
    }
  }

  /// Dispose all stream controllers for settings in this group.
  void dispose() {
    for (final setting in items) {
      setting.dispose();
    }
  }
}
