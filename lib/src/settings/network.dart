import 'setting.dart';
import 'settings_group.dart';

/// Network settings group containing all network-related preferences.
final networkSettings = SettingsGroup(
  key: 'network',
  items: [
    /// Persistent device ID for network coordination
    StringSetting(key: 'device_id', defaultValue: ''),
    /// Human-readable device name for network coordination
    StringSetting(key: 'device_name', defaultValue: ''),
    /// Whether to use local network mode (true) or network coordination (false)
    BoolSetting(key: 'use_local_network', defaultValue: false),
    /// Network timeout for coordination operations in seconds
    DoubleSetting(key: 'coordination_timeout', defaultValue: 10.0),
    /// Performance preset for network communication
    StringSetting(key: 'performance_preset', defaultValue: 'balanced'),
  ],
);