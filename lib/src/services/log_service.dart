import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

mixin class AppLogging {
  final LogService appLog = LogService();
}

class LogEntry {
  final DateTime timestamp;
  final Level level;
  final String message;
  final String? logger;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.logger,
    this.error,
    this.stackTrace,
  });

  String format() {
    final buffer = StringBuffer();
    buffer.write('${timestamp.toIso8601String()} ');
    buffer.write('[${level.name.toUpperCase().padRight(8)}] ');
    if (logger != null) buffer.write('$logger: ');
    buffer.write(message);
    if (error != null) buffer.write(' | Error: $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return buffer.toString();
  }
}

class LogService {
  static final LogService _instance = LogService._internal();
  static LogService get instance => _instance;
  static const String defaultLoggerName = 'RiseTogether-App';

  final Queue<LogEntry> _buffer = Queue<LogEntry>();
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  Timer? _flushTimer;
  Isolate? _fileIsolate;
  SendPort? _fileSendPort;

  bool _isFileLoggingEnabled = false;
  String? _logFilePath;
  Level _minLevel = Level.ALL;

  static const int _bufferSize = 100;
  static const Duration _flushInterval = Duration(seconds: 1);

  factory LogService() => _instance;

  LogService._internal() {
    _initializeLogger();
    _setupPeriodicFlush();
  }

  void _initializeLogger() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      final level = record.level;
      if (level >= _minLevel) {
        _addEntry(
          LogEntry(
            timestamp: record.time,
            level: level,
            message: record.message,
            logger: record.loggerName,
            error: record.error,
            stackTrace: record.stackTrace,
          ),
        );
      }
    });
  }

  void _setupPeriodicFlush() {
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushBuffer());
  }

  void _addEntry(LogEntry entry) {
    _buffer.add(entry);
    _controller.add(entry);

    if (kDebugMode) {
      debugPrint(entry.format());
    }

    if (_buffer.length >= _bufferSize) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    if (_buffer.isEmpty || !_isFileLoggingEnabled || _fileSendPort == null) {
      return;
    }

    final entries = List<LogEntry>.from(_buffer);
    _buffer.clear();

    _fileSendPort!.send(entries);
  }

  Future<void> enableFileLogging({String? customPath}) async {
    if (_isFileLoggingEnabled) return;

    try {
      _logFilePath = customPath ?? 'logs/app.log';

      final receivePort = ReceivePort();
      _fileIsolate = await Isolate.spawn(_fileLoggingIsolate, [
        receivePort.sendPort,
        _logFilePath!,
      ]);

      _fileSendPort = await receivePort.first as SendPort;
      _isFileLoggingEnabled = true;
    } catch (e) {
      debugPrint('Failed to enable file logging: $e');
    }
  }

  static void _fileLoggingIsolate(List<dynamic> args) async {
    final SendPort mainSendPort = args[0];
    final String logFilePath = args[1];

    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    IOSink? logFile;

    try {
      final file = File(logFilePath);
      await file.parent.create(recursive: true);
      logFile = file.openWrite(mode: FileMode.append);

      await for (final data in receivePort) {
        if (data is List<LogEntry>) {
          for (final entry in data) {
            logFile.writeln(entry.format());
          }
          await logFile.flush();
        }
      }
    } catch (e) {
      debugPrint('File logging isolate error: $e');
    } finally {
      await logFile?.close();
    }
  }

  void setMinLevel(Level level) {
    _minLevel = level;
  }

  Stream<LogEntry> get logStream => _controller.stream;

  void log(
    String message, {
    Level level = Level.INFO,
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).log(level, message, error, stackTrace);
  }

  void finest(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).finest(message, error, stackTrace);
  }

  void finer(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).finer(message, error, stackTrace);
  }

  void fine(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).fine(message, error, stackTrace);
  }

  void config(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).config(message, error, stackTrace);
  }

  void info(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).info(message, error, stackTrace);
  }

  void warning(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).warning(message, error, stackTrace);
  }

  void severe(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).severe(message, error, stackTrace);
  }

  void shout(
    String message, {
    String? logger,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger(logger ?? defaultLoggerName).shout(message, error, stackTrace);
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushBuffer();
    await _controller.close();
    _fileIsolate?.kill();
  }
}
