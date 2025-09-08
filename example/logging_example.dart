import 'package:flutter/foundation.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Example showing how to use the enhanced LogService
class LoggingExample {
  static final LogService _logService = LogService.instance;

  /// Initialize the complete logging system
  static Future<void> initializeLogging() async {
    // Option 1: Initialize everything at once
    await _logService.initializeCompleteLogging(
      appLogDestination: LogDestination.both, // Log to both console and file
      dataLoggers: ['network_data', 'sensor_data', 'user_actions'],
      dataLogFormat: 'tsv', // or 'csv'
    );

    // Option 2: Manual setup (alternative approach)
    // await _logService.configureAppLogging(
    //   destination: LogDestination.both,
    // );
    // await _logService.createDataLogger('network_data');
    // await _logService.createDataLogger('sensor_data');

    debugPrint('Logging system initialized successfully!');
    debugPrint('Status: ${_logService.getLoggingStatus()}');
  }

  /// Example of logging app events
  static void logAppEvents() {
    // Standard app logging - goes to console and/or file based on configuration
    _logService.info('Application started');
    _logService.warning('This is a warning message');
    _logService.severe('This is an error message');

    // With custom logger name
    _logService.info('User logged in', logger: 'Authentication');
    _logService.config('Debug configuration loaded', logger: 'Config');
  }

  /// Example of logging high-frequency data
  static void logNetworkData() {
    // High-frequency data logging - bypasses console, goes directly to file
    _logService.logData(
      'network_data',
      'RECEIVED',
      data: {
        'bytes': 1024,
        'latency_ms': 45,
        'source_ip': '192.168.1.100',
        'protocol': 'TCP',
      },
    );

    _logService.logData(
      'network_data',
      'SENT',
      data: {
        'bytes': 512,
        'destination_ip': '192.168.1.200',
        'protocol': 'UDP',
      },
    );
  }

  /// Example of logging sensor data
  static void logSensorData() {
    _logService.logData(
      'sensor_data',
      'ACCELEROMETER',
      data: {
        'x': 0.5,
        'y': -0.3,
        'z': 9.8,
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      },
    );

    _logService.logData(
      'sensor_data',
      'GYROSCOPE',
      data: {'pitch': 10.2, 'roll': -5.7, 'yaw': 180.0},
    );
  }

  /// Example of logging user actions
  static void logUserAction(String action, Map<String, dynamic> context) {
    _logService.logData('user_actions', action, data: context);
  }

  /// Clean up logging system (call this when app shuts down)
  static Future<void> cleanup() async {
    await _logService.dispose();
  }
}

/// Usage example in your main.dart or service initialization:
/*
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize logging system
  await LoggingExample.initializeLogging();
  
  // Your app initialization...
  runApp(MyApp());
}

// In your app code:
class NetworkService {
  void sendData(List<int> data) {
    // Send the data...
    
    // Log the network activity
    LoggingExample.logNetworkData();
  }
}

class GameController {
  void onPlayerAction(String action) {
    // Handle the action...
    
    // Log user action
    LoggingExample.logUserAction(action, {
      'player_id': 'player123',
      'game_state': 'active',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
*/
