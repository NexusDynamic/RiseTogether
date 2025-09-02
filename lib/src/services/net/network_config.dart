import 'dart:io';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:rise_together/src/settings/app_settings.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Configuration helper for RiseTogether network settings
class RiseTogetherNetworkConfig with AppSettings, AppLogging {
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;
  static String? _cachedDeviceUId;
  static RiseTogetherNetworkConfig? _instance;

  // Singleton pattern to access settings
  static RiseTogetherNetworkConfig get _config {
    _instance ??= RiseTogetherNetworkConfig();
    return _instance!;
  }

  /// Generate a unique device ID based on platform info (cached and persistent)
  static String generateDeviceId() {
    if (_cachedDeviceId != null) {
      _config.appLog.fine(
        'NetworkConfig: Using cached device ID: $_cachedDeviceId',
      );
      return _cachedDeviceId!;
    }

    _config.appLog.info('NetworkConfig: Generating new device ID...');

    // Try to get from app settings first
    try {
      final savedDeviceId = _config.appSettings.getString('device.device_id');
      if (savedDeviceId.isNotEmpty) {
        _cachedDeviceId = savedDeviceId;
        _config.appLog.info(
          'NetworkConfig: Loaded device ID from settings: $_cachedDeviceId',
        );
        return _cachedDeviceId!;
      }
    } catch (e) {
      _config.appLog.warning(
        'NetworkConfig: Settings not available yet, continuing with generation: $e',
      );
    }

    // Generate new device ID
    final platform = Platform.operatingSystem;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hostname = Platform.localHostname;

    _cachedDeviceId = 'rise_${platform}_${hostname}_$timestamp';

    _config.appLog.info(
      'NetworkConfig: Generated new device ID: $_cachedDeviceId',
    );

    // Save to settings for persistence
    try {
      _config.appSettings.setString('device.device_id', _cachedDeviceId!);
      _config.appLog.fine('NetworkConfig: Saved device ID to settings');
    } catch (e) {
      _config.appLog.warning(
        'NetworkConfig: Failed to save device ID to settings: $e',
      );
      // Settings not available, will save later
    }

    return _cachedDeviceId!;
  }

  /// Generate a human-readable device name (cached and persistent)
  static String generateDeviceName() {
    if (_cachedDeviceName != null) {
      return _cachedDeviceName!;
    }

    // Try to get from app settings first
    try {
      final savedDeviceName = _config.appSettings.getString(
        'device.device_name',
      );
      if (savedDeviceName.isNotEmpty) {
        _cachedDeviceName = savedDeviceName;
        return _cachedDeviceName!;
      }
    } catch (e) {
      // Settings not available yet, continue with generation
    }

    // Generate new device name
    final platform = Platform.operatingSystem;
    final hostname = Platform.localHostname;

    _cachedDeviceName = 'RiseTogether_${platform}_$hostname';

    // Save to settings for persistence
    try {
      _config.appSettings.setString('device.device_name', _cachedDeviceName!);
    } catch (e) {
      // Settings not available, will save later
    }

    return _cachedDeviceName!;
  }

  static String generateDeviceUId() {
    if (_cachedDeviceUId != null) {
      return _cachedDeviceUId!;
    }

    // Try to get from app settings first
    try {
      final savedDeviceUId = _config.appSettings.getString('device.device_uid');
      if (savedDeviceUId.isNotEmpty) {
        _cachedDeviceUId = savedDeviceUId;
        return _cachedDeviceUId!;
      }
    } catch (e) {
      // Settings not available yet, continue with generation
    }

    // Generate new device UId
    _cachedDeviceUId = generateUid();

    // Save to settings for persistence
    try {
      _config.appSettings.setString('device.device_uid', _cachedDeviceUId!);
    } catch (e) {
      // Settings not available, will save later
    }

    return _cachedDeviceUId!;
  }

  /// Get platform information for metadata
  static Map<String, dynamic> getPlatformInfo() {
    return {
      'platform': Platform.operatingSystem,
      'hostname': Platform.localHostname,
      'game': 'rise_together',
      'version': '1.0.0',
    };
  }
}
