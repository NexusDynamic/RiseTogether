import 'dart:convert';
import 'dart:async';
import 'package:rise_together/src/attributes/serializable.dart';

/// Enum for supported setting value types.
///
/// This enum is used internally to track the type of each setting
/// and ensure proper type casting during storage and retrieval operations.
enum SettingType {
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
abstract class Setting<T> implements Serializable {
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
  final SettingType type;

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
  void notifyChange(T value) {
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
  bool validate(T value) {
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

  /// Converts the setting to a map.
  @override
  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'type': type.name,
      'defaultValue': defaultValue,
      'userConfigurable': userConfigurable,
      // Todo: convert validator to use validation classes (e.g. RangeValidator)
      'validator': null,
    };
  }

  /// Creates a setting from a map representation.
  Setting.fromMap(Map<String, dynamic> map)
    : key = map['key'] as String,
      type = SettingType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () =>
            throw ArgumentError('Invalid setting type: ${map['type']}'),
      ),
      defaultValue = map['defaultValue'] as T,
      userConfigurable = map['userConfigurable'] as bool? ?? true,
      validator = null;

  /// Converts the setting to a JSON string representation.
  @override
  String toJson() {
    return jsonEncode(toMap());
  }

  /// Creates a setting from a JSON string representation.
  Setting.fromJson(String json)
    : this.fromMap(jsonDecode(json) as Map<String, dynamic>);
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
  }) : super(type: SettingType.bool);

  /// Converts the boolean value to a JSON string representation.
  @override
  String toJson() {
    return defaultValue.toString();
  }

  /// Creates a boolean setting from a JSON string representation.
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
  }) : super(type: SettingType.int);
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
  }) : super(type: SettingType.double);
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
  }) : super(type: SettingType.string);
}
