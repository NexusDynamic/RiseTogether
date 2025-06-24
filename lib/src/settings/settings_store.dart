import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'exceptions.dart';

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
