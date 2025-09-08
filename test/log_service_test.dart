import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together/src/services/log_service.dart';

void main() {
  group('LogService File Logging Tests', () {
    late LogService logService;
    late String tempLogPath;
    late Directory tempDir;

    setUp(() async {
      logService = LogService.newInstance();
      tempDir = await Directory.systemTemp.createTemp('log_test_');
      tempLogPath = '${tempDir.path}/test.log';
    });

    tearDown(() async {
      // Force cleanup
      try {
        if (logService.isAppFileLoggingEnabled) {
          await logService.disableAppFileLogging();
        }
      } catch (e) {
        // Force kill if timeout
        logService.forceCleanup();
      }

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should enable and disable app file logging successfully', () async {
      expect(logService.isAppFileLoggingEnabled, false);

      await logService.enableAppFileLogging(customPath: tempLogPath);
      expect(logService.isAppFileLoggingEnabled, true);
      expect(File(tempLogPath).parent.existsSync(), true);

      await logService.disableAppFileLogging();
      expect(logService.isAppFileLoggingEnabled, false);
    });

    test('should write app log entries to file', () async {
      // Configure app logging to write to file
      await logService.configureAppLogging(
        destination: LogDestination.file,
        filePath: tempLogPath,
      );

      logService.info('Test message 1');
      logService.warning('Test message 2');
      logService.severe('Test message 3');

      // Wait a bit for async operations
      await Future.delayed(Duration(milliseconds: 200));

      // Force flush by disposing
      await logService.dispose();

      final logFile = File(tempLogPath);
      expect(logFile.existsSync(), true);

      final content = await logFile.readAsString();
      expect(content.contains('Test message 1'), true);
      expect(content.contains('Test message 2'), true);
      expect(content.contains('Test message 3'), true);
      expect(content.contains('[INFO    ]'), true);
      expect(content.contains('[WARNING ]'), true);
      expect(content.contains('[SEVERE  ]'), true);
    });

    test('should handle high-frequency data logging (TSV format)', () async {
      const loggerName = 'eeg_data';
      final dataLogPath = '${tempDir.path}/eeg_data.tsv';

      // Create a data logger
      await logService.createFileLogger(
        loggerName,
        filePath: dataLogPath,
        format: 'tsv',
      );

      // Simulate high-frequency EEG data (100Hz for simplicity)
      const int totalEntries = 100;

      for (int i = 0; i < totalEntries; i++) {
        logService.logData(
          loggerName,
          'EEG_SAMPLE',
          data: {'channel_1': i * 0.1, 'channel_2': i * 0.2, 'sample_id': i},
        );
      }

      // Wait for buffer flush and dispose
      await Future.delayed(Duration(milliseconds: 100));
      await logService.dispose();

      final logFile = File(dataLogPath);
      expect(logFile.existsSync(), true);

      final content = await logFile.readAsString();
      final lines = content
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

      expect(lines.length, totalEntries);

      // Check TSV format (tab-separated)
      expect(lines[0].contains('\t'), true);
      expect(lines[0].contains('EEG_SAMPLE'), true);
      expect(lines[0].contains('channel_1:0.0'), true);
      expect(lines[99].contains('sample_id:99'), true);
    });

    test('should handle concurrent logging safely', () async {
      await logService.configureAppLogging(
        destination: LogDestination.file,
        filePath: tempLogPath,
      );

      // Create multiple futures that log concurrently
      final futures = List.generate(10, (index) async {
        for (int i = 0; i < 50; i++) {
          logService.info('Thread_${index}_Message_$i');
          if (i % 10 == 0) {
            await Future.delayed(Duration(microseconds: 100));
          }
        }
      });

      await Future.wait(futures);
      await Future.delayed(Duration(milliseconds: 300));
      await logService.dispose();

      final logFile = File(tempLogPath);
      final content = await logFile.readAsString();
      final lines = content
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

      // Should have all 500 messages (10 threads * 50 messages)
      expect(lines.length, 500);

      // Check that messages from different threads are present
      expect(content.contains('Thread_0_Message_0'), true);
      expect(content.contains('Thread_9_Message_49'), true);
    });

    test('should respect buffer size and flush immediately', () async {
      await logService.configureAppLogging(
        destination: LogDestination.file,
        filePath: tempLogPath,
      );

      // Log exactly buffer size + 1 to trigger immediate flush
      const bufferSize = 100; // From LogService._bufferSize
      for (int i = 0; i <= bufferSize; i++) {
        logService.info('Buffer test message $i');
      }

      // Small delay for flush to complete
      await Future.delayed(Duration(milliseconds: 100));

      final logFile = File(tempLogPath);
      expect(logFile.existsSync(), true);

      final content = await logFile.readAsString();
      final lines = content
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

      // Should have at least the buffer size entries flushed
      expect(lines.length, greaterThanOrEqualTo(bufferSize));
    });

    test('should handle isolate timeout gracefully', () async {
      // This test is harder to implement without mocking, but we can test
      // that enable/disable don't hang
      final stopwatch = Stopwatch()..start();

      await logService.enableAppFileLogging(customPath: tempLogPath);
      await logService.disableAppFileLogging();

      stopwatch.stop();

      // Should complete within reasonable time (much less than 5s timeout)
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('should preserve log order under high load', () async {
      await logService.configureAppLogging(
        destination: LogDestination.file,
        filePath: tempLogPath,
      );

      // Log sequential numbered messages rapidly
      const int messageCount = 200;
      for (int i = 0; i < messageCount; i++) {
        logService.info('SEQUENCE_$i');
      }

      await Future.delayed(Duration(milliseconds: 300));
      await logService.dispose();

      final logFile = File(tempLogPath);
      final content = await logFile.readAsString();
      final lines = content
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

      expect(lines.length, messageCount);

      // Check that first and last messages are in correct positions
      expect(lines[0].contains('SEQUENCE_0'), true);
      expect(
        lines[messageCount - 1].contains('SEQUENCE_${messageCount - 1}'),
        true,
      );

      // Verify sequential order (at least first 10 and last 10)
      for (int i = 0; i < 10; i++) {
        expect(lines[i].contains('SEQUENCE_$i'), true);
      }
      for (int i = messageCount - 10; i < messageCount; i++) {
        expect(lines[i].contains('SEQUENCE_$i'), true);
      }
    });

    test('should handle multiple enable/disable cycles', () async {
      for (int cycle = 0; cycle < 3; cycle++) {
        final cyclePath = '${tempDir.path}/cycle_$cycle.log';

        await logService.configureAppLogging(
          destination: LogDestination.file,
          filePath: cyclePath,
        );

        logService.info('Cycle $cycle message 1');
        logService.info('Cycle $cycle message 2');

        await Future.delayed(Duration(milliseconds: 100));
        await logService.dispose();

        // Create new instance for next cycle
        logService = LogService.newInstance();

        final logFile = File(cyclePath);
        expect(logFile.existsSync(), true);

        final content = await logFile.readAsString();
        expect(content.contains('Cycle $cycle message 1'), true);
        expect(content.contains('Cycle $cycle message 2'), true);
      }
    });

    test('should format TSV data correctly', () async {
      const loggerName = 'tsv_test';
      final tsvPath = '${tempDir.path}/test.tsv';

      await logService.createFileLogger(
        loggerName,
        filePath: tsvPath,
        format: 'tsv',
      );

      // Log structured data
      logService.logData(
        loggerName,
        'TEST_SAMPLE',
        data: {'value1': 123.45, 'value2': 'text_data', 'value3': true},
      );

      await Future.delayed(Duration(milliseconds: 100));
      await logService.dispose();

      final content = await File(tsvPath).readAsString();
      final lines = content.split('\n').where((l) => l.isNotEmpty).toList();

      expect(lines.length, 1);

      // Check TSV format: timestamp \t message \t data entries (tab-separated)
      final parts = lines[0].split('\t');
      expect(
        parts.length,
        greaterThanOrEqualTo(3),
      ); // timestamp, message, data entries
      expect(parts[1], 'TEST_SAMPLE');

      // Data entries should be in remaining parts
      final dataString = parts.skip(2).join('\t');
      expect(dataString, contains('value1:123.45'));
      expect(dataString, contains('value2:text_data'));
      expect(dataString, contains('value3:true'));
    });

    test('should format CSV data correctly', () async {
      const loggerName = 'csv_test';
      final csvPath = '${tempDir.path}/test.csv';

      await logService.createFileLogger(
        loggerName,
        filePath: csvPath,
        format: 'csv',
      );

      logService.logData(
        loggerName,
        'CSV_SAMPLE',
        data: {'sensor_id': 42, 'temperature': 25.5},
      );

      await Future.delayed(Duration(milliseconds: 100));
      await logService.dispose();

      final content = await File(csvPath).readAsString();
      final lines = content.split('\n').where((l) => l.isNotEmpty).toList();

      expect(lines.length, 1);

      // Check CSV format: "timestamp","message","data"
      expect(lines[0], startsWith('"'));
      expect(lines[0], contains('","CSV_SAMPLE"'));
      expect(lines[0], contains('sensor_id:42'));
      expect(lines[0], contains('temperature:25.5'));
    });

    test('should handle multiple data loggers simultaneously', () async {
      final eegPath = '${tempDir.path}/eeg.tsv';
      final sensorPath = '${tempDir.path}/sensor.csv';

      await logService.createFileLogger(
        'eeg',
        filePath: eegPath,
        format: 'tsv',
      );
      await logService.createFileLogger(
        'sensor',
        filePath: sensorPath,
        format: 'csv',
      );

      // Log to both simultaneously
      for (int i = 0; i < 10; i++) {
        logService.logData('eeg', 'EEG_$i', data: {'channel': i * 0.1});
        logService.logData('sensor', 'SENSOR_$i', data: {'temp': 20 + i});
      }

      await Future.delayed(Duration(milliseconds: 200));
      await logService.dispose();

      // Check both files exist and have correct content
      final eegContent = await File(eegPath).readAsString();
      final sensorContent = await File(sensorPath).readAsString();

      final eegLines = eegContent
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      final sensorLines = sensorContent
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();

      expect(eegLines.length, 10);
      expect(sensorLines.length, 10);

      // Check format differences
      expect(eegLines[0], contains('\t')); // TSV uses tabs
      expect(sensorLines[0], contains('","')); // CSV uses quoted commas

      expect(eegLines[0], contains('EEG_0'));
      expect(sensorLines[0], contains('SENSOR_0'));
    });

    test('should handle app logging with different destinations', () async {
      final filePath = '${tempDir.path}/app_both.log';

      // Test console + file destination
      await logService.configureAppLogging(
        destination: LogDestination.both,
        filePath: filePath,
      );

      logService.info('Both destination test');

      await Future.delayed(Duration(milliseconds: 100));
      await logService.dispose();

      // Check file was created
      expect(File(filePath).existsSync(), true);
      final content = await File(filePath).readAsString();
      expect(content, contains('Both destination test'));
      expect(content, contains('[INFO    ]'));
    });

    test(
      'should fallback gracefully when data logger does not exist',
      () async {
        // Try to log to non-existent logger
        logService.logData(
          'nonexistent',
          'test message',
          data: {'key': 'value'},
        );

        // Should not crash, should fallback to app log
        await Future.delayed(Duration(milliseconds: 50));

        // No exception should be thrown
        expect(true, true); // Test passes if we reach here
      },
    );
  });
}
