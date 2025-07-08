import 'dart:io';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:rise_together/src/settings/app_settings.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Configuration helper for RiseTogether network settings
class RiseTogetherNetworkConfig with AppSettings, AppLogging {
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;
  static RiseTogetherNetworkConfig? _instance;
  
  // Singleton pattern to access settings
  static RiseTogetherNetworkConfig get _config {
    _instance ??= RiseTogetherNetworkConfig();
    return _instance!;
  }
  
  /// Generate a unique device ID based on platform info (cached and persistent)
  static String generateDeviceId() {
    if (_cachedDeviceId != null) {
      _config.appLog.fine('NetworkConfig: Using cached device ID: $_cachedDeviceId');
      return _cachedDeviceId!;
    }
    
    _config.appLog.info('NetworkConfig: Generating new device ID...');
    
    // Try to get from app settings first
    try {
      final savedDeviceId = _config.appSettings.getString('network.device_id');
      if (savedDeviceId.isNotEmpty) {
        _cachedDeviceId = savedDeviceId;
        _config.appLog.info('NetworkConfig: Loaded device ID from settings: $_cachedDeviceId');
        return _cachedDeviceId!;
      }
    } catch (e) {
      _config.appLog.warning('NetworkConfig: Settings not available yet, continuing with generation: $e');
    }
    
    // Generate new device ID
    final platform = Platform.operatingSystem;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hostname = Platform.localHostname;
    
    _cachedDeviceId = 'rise_${platform}_${hostname}_$timestamp';
    
    _config.appLog.info('NetworkConfig: Generated new device ID: $_cachedDeviceId');
    
    // Save to settings for persistence
    try {
      _config.appSettings.setString('network.device_id', _cachedDeviceId!);
      _config.appLog.fine('NetworkConfig: Saved device ID to settings');
    } catch (e) {
      _config.appLog.warning('NetworkConfig: Failed to save device ID to settings: $e');
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
      final savedDeviceName = _config.appSettings.getString('network.device_name');
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
      _config.appSettings.setString('network.device_name', _cachedDeviceName!);
    } catch (e) {
      // Settings not available, will save later
    }
    
    return _cachedDeviceName!;
  }

  /// Create optimized coordination config for RiseTogether
  static CoordinationConfig createCoordinationConfig() {
    return CoordinationConfig(
      discoveryInterval: 2.0,
      heartbeatInterval: 1.0,
      nodeTimeout: 5.0,
      joinTimeout: 10.0,
      maxNodes: 20, // Support up to 20 devices
      autoPromote: true,
      receiveOwnMessages: true, // Enable coordinator participation in game
      capabilities: {
        'game': 'rise_together',
        'version': '0.4.0',
        'supports_high_frequency': true,
        'platform': Platform.operatingSystem,
        'hostname': Platform.localHostname,
      },
    );
  }

  /// Create high-frequency config optimized for paddle actions
  static HighFrequencyConfig createGameDataConfig({
    double? targetFrequency,
    bool? useBusyWait,
  }) {
    return HighFrequencyConfig(
      targetFrequency:
          targetFrequency ?? 500.0, // 500Hz for responsive gameplay
      useBusyWait: useBusyWait ?? true,
      channelFormat: LSLChannelFormat.int32,
      channelCount: 3, // [teamId, actionIndex, playerIdHash]
      bufferSize: 1000,
      useIsolate: true,
    );
  }

  /// Configuration presets for different scenarios
  static HighFrequencyConfig createPerformancePreset(PerformancePreset preset) {
    switch (preset) {
      case PerformancePreset.maxPerformance:
        return HighFrequencyConfig(
          targetFrequency: 1000.0,
          useBusyWait: true,
          channelFormat: LSLChannelFormat.int32,
          channelCount: 3,
          bufferSize: 2000,
          useIsolate: true,
        );
      case PerformancePreset.balanced:
        return HighFrequencyConfig(
          targetFrequency: 500.0,
          useBusyWait: true,
          channelFormat: LSLChannelFormat.int32,
          channelCount: 3,
          bufferSize: 1000,
          useIsolate: true,
        );
      case PerformancePreset.lowCPU:
        return HighFrequencyConfig(
          targetFrequency: 250.0,
          useBusyWait: false,
          channelFormat: LSLChannelFormat.int32,
          channelCount: 3,
          bufferSize: 500,
          useIsolate: true,
        );
    }
  }
}

/// Performance presets for different use cases
enum PerformancePreset {
  /// Maximum performance - 1000Hz, high CPU usage
  maxPerformance,

  /// Balanced - 500Hz, moderate CPU usage (recommended)
  balanced,

  /// Low CPU - 250Hz, minimal CPU usage
  lowCPU,
}
