import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exception thrown when a requested setting is not found.
///
/// This occurs when:
/// - Accessing a setting that doesn't exist in the group
/// - Using an invalid storage key format
/// - Referencing a setting before it's been registered
///
/// Example:
/// ```dart
/// try {
///   Settings.getBool('nonexistent.setting');
/// } catch (e) {
///   if (e is SettingNotFoundException) {
///     print('Setting not found: ${e.message}');
///   }
/// }
/// ```
class SettingNotFoundException implements Exception {
  /// Descriptive error message explaining what setting was not found.
  final String message;

  /// Creates a new [SettingNotFoundException] with the given [message].
  const SettingNotFoundException(this.message);

  @override
  String toString() => 'SettingNotFoundException: $message';
}

/// Exception thrown when attempting to modify a non-configurable setting.
///
/// Settings can be marked as non-configurable by setting `userConfigurable: false`.
/// This is useful for system settings or read-only configuration values.
///
/// Example:
/// ```dart
/// final systemSetting = BoolSetting(
///   key: 'systemFlag',
///   defaultValue: true,
///   userConfigurable: false, // This setting cannot be modified by users
/// );
/// ```
class SettingNotConfigurableException implements Exception {
  /// Descriptive error message explaining which setting cannot be configured.
  final String message;

  /// Creates a new [SettingNotConfigurableException] with the given [message].
  const SettingNotConfigurableException(this.message);

  @override
  String toString() => 'SettingNotConfigurableException: $message';
}

/// Exception thrown when a setting value fails validation.
///
/// This occurs when a validator function returns false for a given value.
/// Validators are useful for ensuring data integrity and business rules.
///
/// Example:
/// ```dart
/// final volumeSetting = DoubleSetting(
///   key: 'volume',
///   defaultValue: 0.5,
///   validator: (value) => value >= 0.0 && value <= 1.0,
/// );
///
/// // This will throw SettingValidationException
/// await Settings.setDouble('audio.volume', 1.5);
/// ```
class SettingValidationException implements Exception {
  /// Descriptive error message explaining the validation failure.
  final String message;

  /// Creates a new [SettingValidationException] with the given [message].
  const SettingValidationException(this.message);

  @override
  String toString() => 'SettingValidationException: $message';
}

/// Exception thrown when attempting to access settings before initialization.
///
/// The settings framework requires asynchronous initialization before use.
/// Always await `Settings.init()` or individual `readyFuture` properties
/// before accessing setting values.
///
/// Example:
/// ```dart
/// // Wrong - may throw SettingsNotReadyException
/// bool value = Settings.getBool('game.sound');
///
/// // Correct - wait for initialization
/// await Settings.init();
/// bool value = Settings.getBool('game.sound');
/// ```
class SettingsNotReadyException implements Exception {
  /// Descriptive error message explaining the readiness issue.
  final String message;

  /// Creates a new [SettingsNotReadyException] with the given [message].
  const SettingsNotReadyException(this.message);

  @override
  String toString() => 'SettingsNotReadyException: $message';
}

/// A singleton store that manages the underlying SharedPreferences with caching.
///
/// This class provides a centralized, cached interface to SharedPreferences,
/// eliminating the need for repeated async calls during normal operation.
/// The store initializes asynchronously but provides synchronous access
/// once ready, improving performance for frequent setting access.
///
/// The store is used internally by the settings framework and typically
/// doesn't need to be accessed directly by application code.
///
/// In test environments, it automatically falls back to regular SharedPreferences
/// to ensure compatibility with test mocking frameworks.
///
/// Example internal usage:
/// ```dart
/// final store = SettingsStore();
/// await store.readyFuture; // Wait for initialization
/// bool value = store.prefs.getBool('some.key') ?? false;
/// ```
class SettingsStore {
  /// The singleton instance of the settings store.
  static SettingsStore? _instance;

  /// Internal flag tracking whether the store is ready for use.
  bool _ready = false;

  /// Public getter indicating if the store has been initialized and is ready.
  /// When true, the [prefs] getter can be used synchronously.
  bool get ready => _ready;

  /// Future that completes when the store is fully initialized.
  /// Await this future before accessing settings to ensure proper initialization.
  late final Future<bool> readyFuture;

  /// Factory constructor that returns the singleton instance.
  /// Multiple calls to this constructor return the same instance.
  factory SettingsStore({bool forceRegularSharedPreferences = false}) {
    _instance ??= SettingsStore._internal(forceRegularSharedPreferences);
    return _instance!;
  }

  /// The SharedPreferences instance (cached or regular depending on environment).
  /// Only accessible after initialization is complete.
  late final dynamic _prefs;

  /// Whether we're using the cached version or regular SharedPreferences.
  bool _isUsingCache = true;

  /// Private constructor that initializes SharedPreferences.
  ///
  /// In debug mode or when [forceRegularSharedPreferences] is true, uses regular
  /// SharedPreferences for better test compatibility. In release mode, uses
  /// SharedPreferencesWithCache for better performance.
  ///
  /// This constructor:
  /// 1. Creates a completer for the ready future
  /// 2. Chooses appropriate SharedPreferences implementation based on environment
  /// 3. Sets up success and error handling
  /// 4. Marks the store as ready when initialization completes
  SettingsStore._internal(bool forceRegularSharedPreferences) {
    final completer = Completer<bool>();
    readyFuture = completer.future;

    // In debug mode or when forced, use regular SharedPreferences for better test compatibility
    // In release mode, use SharedPreferencesWithCache for better performance
    final useRegularSharedPreferences =
        forceRegularSharedPreferences || kDebugMode;

    if (useRegularSharedPreferences) {
      _isUsingCache = false;
      SharedPreferences.getInstance()
          .then((prefs) {
            _prefs = prefs;
            _ready = true;
            completer.complete(true);
          })
          .catchError((error) {
            _ready = false;
            completer.completeError(error);
            throw Exception('Failed to initialize SharedPreferences: $error');
          });
    } else {
      _isUsingCache = true;
      SharedPreferencesWithCache.create(
            cacheOptions: const SharedPreferencesWithCacheOptions(),
          )
          .then((prefs) {
            _prefs = prefs;
            _ready = true;
            completer.complete(true);
          })
          .catchError((error) {
            // If SharedPreferencesWithCache fails, fall back to regular SharedPreferences
            _isUsingCache = false;
            SharedPreferences.getInstance()
                .then((fallbackPrefs) {
                  _prefs = fallbackPrefs;
                  _ready = true;
                  completer.complete(true);
                })
                .catchError((fallbackError) {
                  _ready = false;
                  completer.completeError(fallbackError);
                  throw Exception(
                    'Failed to initialize any SharedPreferences: $fallbackError',
                  );
                });
          });
    }
  }

  /// Reset the singleton instance (useful for testing).
  static void reset() {
    _instance = null;
  }

  /// Provides access to the SharedPreferences instance.
  ///
  /// This getter should only be called after the store is ready.
  /// Use [ready] to check readiness or await [readyFuture] to ensure
  /// the store is initialized before accessing this property.
  ///
  /// Returns either SharedPreferencesWithCache (production) or
  /// SharedPreferences (test environment) depending on initialization.
  ///
  /// Throws: SettingsNotReadyException if accessed before initialization completes.
  dynamic get prefs {
    if (!_ready) {
      throw SettingsNotReadyException(
        'SettingsStore is not ready. Please await readyFuture first.',
      );
    }
    return _prefs;
  }

  /// Returns true if using SharedPreferencesWithCache, false if using regular SharedPreferences.
  bool get isUsingCache => _isUsingCache;
}

/// Enum for supported setting value types.
///
/// This enum is used internally to track the type of each setting
/// and ensure proper type casting during storage and retrieval operations.
enum SettingsType {
  /// Boolean true/false values
  bool,

  /// Integer numeric values
  int,

  /// Double-precision floating point values
  double,

  /// String text values
  string,
}

/// Abstract base class for all setting types.
///
/// This class defines the common interface and functionality for all settings,
/// including type safety, validation, change notifications, and metadata.
///
/// Type parameter [T] ensures compile-time type safety for setting values.
///
/// Example usage:
/// ```dart
/// // Create a validated volume setting
/// final volumeSetting = DoubleSetting(
///   key: 'volume',
///   defaultValue: 0.5,
///   validator: (value) => value >= 0.0 && value <= 1.0,
/// );
///
/// // Listen for changes
/// volumeSetting.stream.listen((newValue) {
///   print('Volume changed to: $newValue');
/// });
/// ```
///
/// Concrete implementations:
/// - [BoolSetting] for boolean values
/// - [IntSetting] for integer values
/// - [DoubleSetting] for floating-point values
/// - [StringSetting] for text values
abstract class Setting<T> {
  /// Internal stream controller for broadcasting value changes.
  /// Uses broadcast to allow multiple listeners.
  final StreamController<T> _controller = StreamController<T>.broadcast();

  /// Unique identifier for this setting within its group.
  ///
  /// Keys should be descriptive and follow camelCase convention.
  /// Examples: 'soundEnabled', 'maxRetries', 'serverUrl'
  final String key;

  /// The data type of this setting's value.
  ///
  /// Used internally for type checking and storage operations.
  /// Automatically set by concrete implementations.
  final SettingsType type;

  /// The default value used when the setting hasn't been explicitly set.
  ///
  /// This value is used during initialization and reset operations.
  /// Must match the generic type parameter [T].
  final T defaultValue;

  /// Whether this setting can be modified by user code.
  ///
  /// When false, attempts to modify the setting will throw
  /// [SettingNotConfigurableException]. Useful for system settings
  /// or read-only configuration values.
  ///
  /// Defaults to true.
  final bool userConfigurable;

  /// Optional function to validate setting values before storage.
  ///
  /// The validator receives the new value and should return:
  /// - `true` if the value is valid
  /// - `false` if the value should be rejected
  ///
  /// When validation fails, [SettingValidationException] is thrown.
  ///
  /// Example:
  /// ```dart
  /// validator: (value) => value >= 0 && value <= 100
  /// ```
  final bool Function(T)? validator;

  /// Stream that emits new values when the setting changes.
  ///
  /// This stream uses broadcast semantics, allowing multiple listeners.
  /// The stream emits the new value immediately after it's stored.
  ///
  /// Example:
  /// ```dart
  /// setting.stream.listen((newValue) {
  ///   print('Setting changed to: $newValue');
  ///   updateUI(newValue);
  /// });
  /// ```
  Stream<T> get stream => _controller.stream;

  /// Creates a new setting with the specified configuration.
  ///
  /// Parameters:
  /// - [key]: Unique identifier within the settings group
  /// - [type]: Data type of the setting value
  /// - [defaultValue]: Initial/reset value for the setting
  /// - [userConfigurable]: Whether the setting can be modified (default: true)
  /// - [validator]: Optional validation function for new values
  Setting({
    required this.key,
    required this.type,
    required this.defaultValue,
    this.userConfigurable = true,
    this.validator,
  });

  /// Internal method to notify all stream listeners of a value change.
  ///
  /// This method is called automatically by the settings framework
  /// after a value has been successfully stored. Application code
  /// should not call this method directly.
  ///
  /// Parameters:
  /// - [value]: The new value that was stored
  void _notifyChange(T value) {
    _controller.add(value);
  }

  /// Internal method to validate a value using the validator function.
  ///
  /// Returns true if no validator is provided or if the validator
  /// function returns true. Returns false if validation fails.
  ///
  /// Parameters:
  /// - [value]: The value to validate
  ///
  /// Returns: true if valid, false if invalid
  bool _validate(T value) {
    return validator?.call(value) ?? true;
  }

  /// Dispose of the stream controller and release resources.
  ///
  /// This method should be called when the setting is no longer needed
  /// to prevent memory leaks. It's automatically called by the settings
  /// framework when disposing of setting groups.
  ///
  /// After calling dispose, the [stream] will no longer emit events.
  void dispose() {
    _controller.close();
  }
}

/// A setting that stores boolean (true/false) values.
///
/// This is a concrete implementation of [Setting] specialized for boolean values.
/// Commonly used for feature flags, toggles, and binary preferences.
///
/// Example:
/// ```dart
/// final soundEnabled = BoolSetting(
///   key: 'soundEnabled',
///   defaultValue: true,
/// );
///
/// final debugMode = BoolSetting(
///   key: 'debugMode',
///   defaultValue: false,
///   userConfigurable: false, // System setting
/// );
/// ```
class BoolSetting extends Setting<bool> {
  /// Creates a new boolean setting.
  ///
  /// Parameters:
  /// - [key]: Unique identifier for this setting
  /// - [defaultValue]: Initial boolean value (true or false)
  /// - [userConfigurable]: Whether users can modify this setting (default: true)
  /// - [validator]: Optional validation function for boolean values
  BoolSetting({
    required super.key,
    required super.defaultValue,
    super.userConfigurable,
    super.validator,
  }) : super(type: SettingsType.bool);
}

/// A setting that stores integer numeric values.
///
/// This is a concrete implementation of [Setting] specialized for integer values.
/// Useful for counts, limits, indices, and whole number preferences.
///
/// Example:
/// ```dart
/// final maxRetries = IntSetting(
///   key: 'maxRetries',
///   defaultValue: 3,
///   validator: (value) => value >= 0 && value <= 10,
/// );
///
/// final fontSize = IntSetting(
///   key: 'fontSize',
///   defaultValue: 14,
///   validator: (value) => value >= 8 && value <= 72,
/// );
/// ```
class IntSetting extends Setting<int> {
  /// Creates a new integer setting.
  ///
  /// Parameters:
  /// - [key]: Unique identifier for this setting
  /// - [defaultValue]: Initial integer value
  /// - [userConfigurable]: Whether users can modify this setting (default: true)
  /// - [validator]: Optional validation function (e.g., range checking)
  IntSetting({
    required super.key,
    required super.defaultValue,
    super.userConfigurable,
    super.validator,
  }) : super(type: SettingsType.int);
}

/// A setting that stores double-precision floating-point values.
///
/// This is a concrete implementation of [Setting] specialized for decimal values.
/// Perfect for percentages, ratios, measurements, and precise numeric settings.
///
/// Example:
/// ```dart
/// final volume = DoubleSetting(
///   key: 'volume',
///   defaultValue: 0.8,
///   validator: (value) => value >= 0.0 && value <= 1.0,
/// );
///
/// final animationSpeed = DoubleSetting(
///   key: 'animationSpeed',
///   defaultValue: 1.0,
///   validator: (value) => value > 0.0 && value <= 5.0,
/// );
/// ```
class DoubleSetting extends Setting<double> {
  /// Creates a new double setting.
  ///
  /// Parameters:
  /// - [key]: Unique identifier for this setting
  /// - [defaultValue]: Initial floating-point value
  /// - [userConfigurable]: Whether users can modify this setting (default: true)
  /// - [validator]: Optional validation function (e.g., range checking)
  DoubleSetting({
    required super.key,
    required super.defaultValue,
    super.userConfigurable,
    super.validator,
  }) : super(type: SettingsType.double);
}

/// A setting that stores string text values.
///
/// This is a concrete implementation of [Setting] specialized for text values.
/// Ideal for names, URLs, file paths, themes, and textual preferences.
///
/// Example:
/// ```dart
/// final theme = StringSetting(
///   key: 'theme',
///   defaultValue: 'light',
///   validator: (value) => ['light', 'dark', 'auto'].contains(value),
/// );
///
/// final serverUrl = StringSetting(
///   key: 'serverUrl',
///   defaultValue: 'https://api.example.com',
///   validator: (value) => Uri.tryParse(value) != null,
/// );
/// ```
class StringSetting extends Setting<String> {
  /// Creates a new string setting.
  ///
  /// Parameters:
  /// - [key]: Unique identifier for this setting
  /// - [defaultValue]: Initial text value
  /// - [userConfigurable]: Whether users can modify this setting (default: true)
  /// - [validator]: Optional validation function (e.g., format checking)
  StringSetting({
    required super.key,
    required super.defaultValue,
    super.userConfigurable,
    super.validator,
  }) : super(type: SettingsType.string);
}

/// A container that groups related settings together for organization.
///
/// [SettingsGroup] extends [UnmodifiableMapBase] to provide convenient
/// map-like access to settings while preventing external modification
/// of the group structure.
///
/// This class is used internally by [SettingsBase] to organize and
/// manage collections of related settings. It provides key-based access
/// and iteration capabilities.
///
/// Example:
/// ```dart
/// final audioSettings = SettingsGroup(items: [
///   BoolSetting(key: 'enabled', defaultValue: true),
///   DoubleSetting(key: 'volume', defaultValue: 0.8),
///   StringSetting(key: 'device', defaultValue: 'default'),
/// ]);
///
/// // Access settings like a map
/// Setting volumeSetting = audioSettings['volume'];
/// ```
class SettingsGroup extends UnmodifiableMapBase<String, Setting> {
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

  /// Creates a new settings group containing the specified settings.
  ///
  /// The provided [items] are converted to an immutable set, and their
  /// keys are extracted for efficient access. Duplicate keys within
  /// the same group are not allowed and will cause undefined behavior.
  ///
  /// Parameters:
  /// - [items]: Collection of settings to include in this group
  ///
  /// Example:
  /// ```dart
  /// final group = SettingsGroup(items: [
  ///   BoolSetting(key: 'notifications', defaultValue: true),
  ///   IntSetting(key: 'timeout', defaultValue: 30),
  /// ]);
  /// ```
  SettingsGroup({required Iterable<Setting> items}) {
    this.items = Set<Setting>.from(items);
    _keys = items.map((item) => item.key).toSet();
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
}

/// Base class for managing a group of related settings.
///
/// [SettingsBase] provides the core functionality for a collection of settings,
/// including initialization, type-safe access, validation, change notifications,
/// and persistence. Each instance represents a logical group of settings
/// (e.g., 'game', 'ui', 'network') with a unique namespace.
///
/// Usage pattern:
/// ```dart
/// // 1. Define your settings
/// final gameSettings = SettingsBase(
///   key: 'game',
///   items: SettingsGroup(items: [
///     BoolSetting(key: 'soundEnabled', defaultValue: true),
///     DoubleSetting(key: 'volume', defaultValue: 0.8),
///   ]),
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
///
/// The class handles all the complexity of storage, type conversion, and
/// error handling, providing a clean interface for application code.
class SettingsBase {
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

  /// Container holding all settings that belong to this group.
  ///
  /// Provides map-like access to individual settings by their keys.
  /// The group is immutable once created to ensure consistency.
  final SettingsGroup items;

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

  /// Creates a new base settings instance with the given key and items.
  /// If you need to ensure settings are initialized before use, you should
  /// await the [readyFuture] before accessing any settings.
  SettingsBase({
    required this.key,
    required this.items,
    bool forceRegularSharedPreferences = false,
  }) {
    _store = SettingsStore(
      forceRegularSharedPreferences: forceRegularSharedPreferences,
    );
    _readyCompleter = Completer<bool>();
    // Initialize the settings in the storage if they haven't been set yet.
    _init();
  }

  /// Creates a new base settings instance optimized for testing.
  /// This constructor forces the use of regular SharedPreferences instead
  /// of SharedPreferencesWithCache to avoid test compatibility issues.
  SettingsBase.forTesting({required this.key, required this.items}) {
    _store = SettingsStore(forceRegularSharedPreferences: true);
    _readyCompleter = Completer<bool>();
    // Initialize the settings in the storage if they haven't been set yet.
    _init();
  }

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
      for (final Setting setting in items.values) {
        final storageKey = _storageKey(setting.key);
        if (!_store.prefs.containsKey(storageKey)) {
          // If the setting is not set, initialize it with the default value.
          await _set(storageKey, setting, null, force: true);
        } else {
          // Validate existing value and reset to default if invalid
          try {
            final currentValue = _get(setting);
            if (setting.validator != null && !setting._validate(currentValue)) {
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
    final setting = items[key];
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
    if (setting is Setting<T> && !setting._validate(value)) {
      throw SettingValidationException(
        'Invalid value for setting $storageKey: $value',
      );
    }

    await _set(storageKey, setting, value);

    // Notify change listeners
    if (setting is Setting<T>) {
      setting._notifyChange(value);
    }
  }

  /// Convenience method to get a typed value of a setting by its key.
  /// Throws an error if the setting is not found or if the type does not match.
  T get<T>(String key) {
    _readySync();
    if (T == dynamic) {
      return getValue(key);
    }
    final setting = items[key];
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
    final setting = items[key];
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
    if (setting.validator != null && !setting._validate(value)) {
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
          case SettingsType.bool:
            return _setBool(storageKey, value as bool);
          case SettingsType.int:
            return _setInt(storageKey, value as int);
          case SettingsType.double:
            return _setDouble(storageKey, value as double);
          case SettingsType.string:
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
    final setting = items[key];
    if (setting == null) {
      throw SettingNotFoundException(
        'No setting in ${this.key} found for key: $key',
      );
    }
    final storageKey = _storageKey(setting.key);
    await _set(storageKey, setting, null, force: true);

    // Notify change listeners
    setting._notifyChange(setting.defaultValue);
  }

  /// Reset all settings in this group to their default values.
  Future<void> resetAll() async {
    await _waitUntilReady();
    for (final setting in items.values) {
      final storageKey = _storageKey(setting.key);
      await _set(storageKey, setting, null, force: true);
      setting._notifyChange(setting.defaultValue);
    }
  }

  /// Dispose all stream controllers for settings in this group.
  void dispose() {
    for (final setting in items.values) {
      setting.dispose();
    }
  }
}

/// Global settings manager providing centralized access to all setting groups.
///
/// The [Settings] class serves as the main entry point for the settings framework,
/// offering static methods for registration, initialization, and access to settings
/// across your entire application. It manages multiple [SettingsBase] groups and
/// provides both individual and batch operations.
///
/// ## Overview
///
/// The settings framework follows a hierarchical structure:
/// ```
/// Settings (Global Manager)
/// │
/// ├── SettingsBase (Group: "game")
/// │   ├── BoolSetting ("soundEnabled")
/// │   └── DoubleSetting ("volume")
/// │
/// └── SettingsBase (Group: "ui")
///     ├── StringSetting ("theme")
///     └── IntSetting ("fontSize")
/// ```
///
/// ## Usage Pattern
///
/// ```dart
/// // 1. Define your setting groups
/// final gameSettings = SettingsBase(
///   key: 'game',
///   items: SettingsGroup(items: [
///     BoolSetting(key: 'soundEnabled', defaultValue: true),
///     DoubleSetting(key: 'volume', defaultValue: 0.8),
///   ]),
/// );
///
/// final uiSettings = SettingsBase(
///   key: 'ui',
///   items: SettingsGroup(items: [
///     StringSetting(key: 'theme', defaultValue: 'light'),
///     IntSetting(key: 'fontSize', defaultValue: 14),
///   ]),
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
  /// This map stores all registered [SettingsBase] instances, providing
  /// fast lookup by group key. Groups must be registered before use.
  static final Map<String, SettingsBase> _settings = {};

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
  static Future<void> init() async {
    final futures = _settings.values.map((settings) => settings.readyFuture);
    await Future.wait(futures);
  }

  /// Returns a map of all registered settings groups.
  static Map<String, SettingsBase> get groups => _settings;

  /// Returns a list of all registered settings groups keys.
  static List<String> get groupKeys => _settings.keys.toList();

  /// Allow access to settings by key using dynamic getters.
  /// This allows you to access settings like:
  /// Settings.game.fullscreen, Settings.game.soundVolume, etc.
  @override
  SettingsBase noSuchMethod(Invocation invocation) {
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
  /// - [settings]: The SettingsBase instance to register
  ///
  /// Throws: [ArgumentError] if a group with the same key already exists
  ///
  /// Example:
  /// ```dart
  /// final gameSettings = SettingsBase(key: 'game', items: [...]);
  /// final uiSettings = SettingsBase(key: 'ui', items: [...]);
  ///
  /// Settings.register(gameSettings);
  /// Settings.register(uiSettings);
  ///
  /// await Settings.init(); // Initialize after all groups are registered
  /// ```
  static void register(SettingsBase settings) {
    if (_settings.containsKey(settings.key)) {
      throw ArgumentError('Settings with key ${settings.key} already exists');
    }
    _settings[settings.key] = settings;
  }

  /// Gets a settings group by its key.
  static SettingsBase getGroup(String key) {
    if (!_settings.containsKey(key)) {
      throw SettingNotFoundException('No settings group found for key: $key');
    }
    return _settings[key]!;
  }

  /// Get a setting by its storage key and type.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found.
  static T get<T>(String storageKey) {
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
  static bool getBool(String storageKey) {
    return get<bool>(storageKey);
  }

  /// Gets a double setting by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not of type int.
  static int getInt(String storageKey) {
    return get<int>(storageKey);
  }

  /// Gets a double setting by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not of type double.
  static double getDouble(String storageKey) {
    return get<double>(storageKey);
  }

  /// Gets a string setting by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not of type string.
  static String getString(String storageKey) {
    return get<String>(storageKey);
  }

  // ===== Setters =====

  /// Sets a setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  static Future<void> setValue(String storageKey, dynamic value) async {
    final id = _parseStorageKey(storageKey);
    final group = getGroup(id.group);
    await group.setValue(id.setting, value);
  }

  /// Sets a setting value by its storage key and type.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  static Future<void> set<T>(String storageKey, T value) async {
    final id = _parseStorageKey(storageKey);
    final group = getGroup(id.group);
    await group.setValue<T>(id.setting, value);
  }

  /// Sets a boolean setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  static Future<void> setBool(String storageKey, bool value) async {
    await set<bool>(storageKey, value);
  }

  /// Sets an integer setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  static Future<void> setInt(String storageKey, int value) async {
    await set<int>(storageKey, value);
  }

  /// Sets a double setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  static Future<void> setDouble(String storageKey, double value) async {
    await set<double>(storageKey, value);
  }

  /// Sets a string setting value by its storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  /// Throws an [ArgumentError] if the storage key is invalid or
  /// if the setting is not found or is not user configurable.
  static Future<void> setString(String storageKey, String value) async {
    await set<String>(storageKey, value);
  }

  /// Sets multiple settings values in a batch operation.
  /// The [settings] map should contain storage keys as keys and values as values.
  /// This is more efficient than setting values individually.
  static Future<void> setMultiple(Map<String, dynamic> settings) async {
    final futures = <Future<void>>[];
    for (final entry in settings.entries) {
      futures.add(setValue(entry.key, entry.value));
    }
    await Future.wait(futures);
  }

  /// Reset a setting to its default value by storage key.
  /// The [storageKey] should be in the format "groupKey.settingKey".
  static Future<void> resetSetting(String storageKey) async {
    final id = _parseStorageKey(storageKey);
    final group = getGroup(id.group);
    await group.reset(id.setting);
  }

  /// Reset all settings in a group to their default values.
  /// The [groupKey] should be the key of the settings group.
  static Future<void> resetGroup(String groupKey) async {
    final group = getGroup(groupKey);
    await group.resetAll();
  }

  /// Reset all settings across all groups to their default values.
  static Future<void> resetAll() async {
    final futures = _settings.values.map((group) => group.resetAll());
    await Future.wait(futures);
  }

  /// Dispose all settings groups and their stream controllers.
  static void dispose() {
    for (final group in _settings.values) {
      group.dispose();
    }
    _settings.clear();
  }

  /// Clear all registered settings groups (for testing purposes).
  static void clearAll() {
    dispose();
  }

  @override
  String toString() {
    return 'Settings{groups: ${_settings.keys.join(', ')}}';
  }
}
