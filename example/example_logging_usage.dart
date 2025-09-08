import 'package:rise_together/src/services/log_service.dart';

void main() async {
  final logService = LogService.instance;

  print('=== RiseTogether Dual Logging System Demo ===\n');

  // 1. App Logging Configuration
  print('1. Configuring App Logging (console + file)...');
  await logService.configureAppLogging(
    destination: LogDestination.both,
    filePath: 'logs/app.log',
  );

  // 2. Create High-Frequency Data Loggers
  print('2. Creating specialized data loggers...');
  
  // EEG data logger (TSV format for analysis tools)
  await logService.createFileLogger(
    'eeg_data',
    filePath: 'logs/eeg_data.tsv',
    format: 'tsv',
  );

  // Sensor data logger (CSV format for spreadsheets)
  await logService.createFileLogger(
    'sensor_data',
    filePath: 'logs/sensor_data.csv',
    format: 'csv',
  );

  // Network metrics logger (TSV format)
  await logService.createFileLogger(
    'network_metrics',
    filePath: 'logs/network_metrics.tsv',
    format: 'tsv',
  );

  print('3. Logging different types of data...\n');

  // 3. App Logging (goes to console and file)
  logService.info('Application started successfully');
  logService.warning('This is a warning message');
  logService.severe('This is an error message');

  // 4. High-frequency EEG data (file only, no console spam)
  print('Simulating high-frequency EEG data logging...');
  for (int i = 0; i < 1000; i++) {
    logService.logData(
      'eeg_data',
      'EEG_SAMPLE',
      data: {
        'timestamp_us': DateTime.now().microsecondsSinceEpoch,
        'channel_1': (i * 0.1) + (0.05 * (i % 10)), // Simulated EEG data
        'channel_2': (i * 0.15) + (0.03 * (i % 7)),
        'channel_3': (i * 0.12) + (0.07 * (i % 5)),
        'sample_id': i,
        'quality': i % 100 == 0 ? 'poor' : 'good',
      },
    );

    // Only delay occasionally to not slow down the demo too much
    if (i % 100 == 0) {
      await Future.delayed(Duration(milliseconds: 1));
    }
  }

  // 5. Sensor data logging
  print('Logging sensor data...');
  for (int i = 0; i < 50; i++) {
    logService.logData(
      'sensor_data',
      'SENSOR_READING',
      data: {
        'accelerometer_x': (i * 0.01),
        'accelerometer_y': (i * 0.02),
        'accelerometer_z': (i * 0.015),
        'gyroscope_x': (i * 0.005),
        'gyroscope_y': (i * 0.008),
        'gyroscope_z': (i * 0.003),
        'temperature': 20.5 + (i * 0.1),
      },
    );
  }

  // 6. Network metrics
  print('Logging network metrics...');
  for (int i = 0; i < 20; i++) {
    logService.logData(
      'network_metrics',
      'NETWORK_STATS',
      data: {
        'latency_ms': 10 + (i * 2),
        'throughput_kbps': 1000 + (i * 50),
        'packet_loss': i % 10 == 0 ? 0.1 : 0.0,
        'connection_count': 5 + (i % 3),
      },
    );
  }

  // 7. More app logging to show it still works
  logService.info('Data logging completed');
  logService.info('EEG samples: 1000, Sensor readings: 50, Network metrics: 20');

  // 8. Wait a bit for all data to be flushed to files
  print('\nWaiting for data to be written to files...');
  await Future.delayed(Duration(seconds: 2));

  // 9. Clean shutdown
  print('Shutting down logging system...');
  await logService.dispose();

  print('\n=== Demo completed! ===');
  print('Check the following files:');
  print('- logs/app.log (app logs in readable format)');
  print('- logs/eeg_data.tsv (high-frequency EEG data)');
  print('- logs/sensor_data.csv (sensor data in CSV format)');
  print('- logs/network_metrics.tsv (network metrics)');
  print('\nNote: App logs also appeared in console, but data logs are file-only for performance.');
}

/// Example usage in a real application
class ExampleEEGApp with AppLogging {
  late final String eegLoggerName = 'eeg_realtime';
  
  Future<void> initialize() async {
    // Setup app logging
    await appLog.configureAppLogging(
      destination: LogDestination.both,
      filePath: 'logs/eeg_app.log',
    );
    
    // Setup high-frequency EEG data logger
    await appLog.createFileLogger(
      eegLoggerName,
      filePath: 'logs/eeg_realtime_${DateTime.now().millisecondsSinceEpoch}.tsv',
      format: 'tsv',
    );
    
    appLog.info('EEG application initialized');
  }
  
  void processEEGSample(Map<String, dynamic> eegData) {
    // Log to high-frequency data logger (no console output)
    appLog.logData(
      eegLoggerName,
      'EEG_SAMPLE',
      data: eegData,
    );
    
    // Only log significant events to app log
    final quality = eegData['quality'] as String?;
    if (quality == 'poor') {
      appLog.warning('Poor signal quality detected in EEG data');
    }
  }
  
  void handleError(String error) {
    // Errors go to app log (console + file)
    appLog.severe('EEG processing error: $error');
  }
}