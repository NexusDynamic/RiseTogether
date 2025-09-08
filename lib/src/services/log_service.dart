import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

mixin class AppLogging {
  final LogService appLog = LogService();
}

extension LogLevelStringExtension on Level {
  static Level fromName(String name) {
    return Level.LEVELS.firstWhere(
      (level) => level.name.toUpperCase() == name.toUpperCase(),
      orElse: () => Level.INFO,
    );
  }
}

abstract interface class LoggingIsolateMessage {
  const LoggingIsolateMessage();
}

@pragma('vm:deeply-immutable')
final class StopMessage implements LoggingIsolateMessage {
  const StopMessage();
}

@pragma('vm:deeply-immutable')
final class ExitedMessage implements LoggingIsolateMessage {
  const ExitedMessage();
}

@pragma('vm:deeply-immutable')
sealed class LogEntry implements LoggingIsolateMessage {
  final String timestamp;
  final String message;

  const LogEntry({required this.timestamp, required this.message});

  String format();
}

@pragma('vm:deeply-immutable')
final class AppLogEntry extends LogEntry {
  final String level;
  final String? logger;

  const AppLogEntry({
    required super.timestamp,
    required this.level,
    required super.message,
    this.logger,
  });

  @override
  String format() {
    final buffer = StringBuffer();
    buffer.write(timestamp);
    buffer.write(' [${level.padRight(8)}] ');
    if (logger != null) buffer.write('$logger: ');
    buffer.write(message);
    return buffer.toString();
  }
}

@pragma('vm:deeply-immutable')
final class DataLogEntry extends LogEntry {
  final String dataString;

  const DataLogEntry({
    required super.timestamp,
    required super.message,
    required this.dataString,
  });

  @override
  String format() {
    final buffer = StringBuffer();
    buffer.write(timestamp);
    buffer.write('\t');
    buffer.write(message);
    if (dataString.isNotEmpty) {
      buffer.write('\t');
      buffer.write(dataString);
    }
    return buffer.toString();
  }
}

enum LogDestination { console, file, both }

@pragma('vm:deeply-immutable')
final class FileLoggerConfig implements LoggingIsolateMessage {
  final String name;
  final String filePath;
  final String formatterType;

  const FileLoggerConfig({
    required this.name,
    required this.filePath,
    required this.formatterType,
  });
}

class LoggerFormatterFactory {
  static String Function(LogEntry) getFormatter(String formatterType) {
    switch (formatterType) {
      case 'app':
        return _appLogFormatter;
      case 'tsv':
        return _tsvDataFormatter;
      case 'csv':
        return _csvDataFormatter;
      default:
        return _defaultFormatter;
    }
  }

  static String _appLogFormatter(LogEntry entry) {
    if (entry is AppLogEntry) {
      return entry.format();
    }
    return '${entry.timestamp} ${entry.message}';
  }

  static String _tsvDataFormatter(LogEntry entry) {
    if (entry is DataLogEntry) {
      return entry.format();
    }
    return '${entry.timestamp}\t${entry.message}';
  }

  static String _csvDataFormatter(LogEntry entry) {
    if (entry is DataLogEntry) {
      final buffer = StringBuffer();
      buffer.write('"${entry.timestamp}",');
      buffer.write('"${entry.message}"');
      if (entry.dataString.isNotEmpty) {
        buffer.write(',"${entry.dataString}"');
      }
      return buffer.toString();
    }
    return '"${entry.timestamp}","${entry.message}"';
  }

  static String _defaultFormatter(LogEntry entry) {
    return '${entry.timestamp} ${entry.message}';
  }
}

class FileLogger {
  final String name;
  final String formatterType;
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription? _subscription;
  final Queue<LogEntry> _buffer = Queue<LogEntry>();
  final Lock _bufferLock = Lock();
  bool _flushPending = false;
  Timer? _flushTimer;

  FileLogger({required this.name, required this.formatterType});

  bool get isEnabled => _isolate != null && _sendPort != null;

  void cleanup() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _buffer.clear();
    _flushPending = false;
  }
}

class LogService {
  static final LogService _instance = LogService._internal();
  static LogService get instance => _instance;
  static const String defaultLoggerName = 'RiseTogether-App';

  final Map<String, FileLogger> _fileLoggers = {};
  final Queue<LogEntry> _appBuffer = Queue<LogEntry>();
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();
  StreamSubscription? _appLogHandlerSubscription;

  final Lock _appBufferLock = Lock();
  bool _appFlushPending = false;

  Timer? _appFlushTimer;
  Isolate? _appFileIsolate;
  SendPort? _appFileSendPort;

  bool _isAppFileLoggingEnabled = false;
  LogDestination _appLogDestination = LogDestination.console;

  String? _appLogDirectory;
  String? _dataLogDirectory;

  @visibleForTesting
  bool get isAppFileLoggingEnabled => _isAppFileLoggingEnabled;

  @visibleForTesting
  void forceCleanup() {
    _appFlushTimer?.cancel();
    _appFlushTimer = null;
    _appFileIsolate?.kill(priority: Isolate.immediate);
    _isAppFileLoggingEnabled = false;
    _appFileIsolate = null;
    _appFileSendPort = null;
    _appLogHandlerSubscription?.cancel();
    _appLogHandlerSubscription = null;
    _isolateCompleter = null;
    _appFlushPending = false;

    // Cleanup file loggers properly
    for (final logger in _fileLoggers.values) {
      logger.cleanup();
    }
    _fileLoggers.clear();
  }

  String? _logFilePath;
  Level _minLevel = Level.INFO;

  Completer<void>? _isolateCompleter;

  // Flush happens when either buffer size reached or interval elapsed
  static const int _bufferSize = 100;
  static const Duration _flushInterval = Duration(seconds: 1);
  static const int _logFlushLines = 20;

  static bool useColors = true;

  bool _initializing = false;
  Completer<void>? _initializeCompleter;

  factory LogService() => _instance;

  @visibleForTesting
  factory LogService.newInstance() => LogService._internal();

  LogService._internal() {
    _initializeLogger();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing || _initializeCompleter != null) {
      return _initializeCompleter?.future;
    }

    _initializing = true;
    _initializeCompleter = Completer<void>();

    try {
      await _initializeLogDirectories();
    } finally {
      _initializing = false;
      _initializeCompleter!.complete();
    }
  }

  Future<void> _initializeLogDirectories() async {
    try {
      if (_appLogDirectory != null && _dataLogDirectory != null) {
        // Already initialized
        return;
      }
      // Get platform-appropriate directories
      Directory? appDir;
      Directory? dataDir;

      if (Platform.isIOS || Platform.isMacOS) {
        // Use app support directory for persistent storage
        appDir = await getApplicationSupportDirectory();
        dataDir = appDir;
      } else if (Platform.isAndroid) {
        // Use external storage or app-specific directory
        try {
          appDir = await getExternalStorageDirectory();
          appDir ??= await getApplicationSupportDirectory();
          dataDir = appDir;
        } catch (e) {
          // Fallback to app support directory
          appDir = await getApplicationSupportDirectory();
          dataDir = appDir;
        }
      } else if (Platform.isWindows || Platform.isLinux) {
        // Use app data directory
        appDir = await getApplicationSupportDirectory();
        dataDir = appDir;
      } else {
        // Fallback for other platforms
        appDir = await getApplicationSupportDirectory();
        dataDir = appDir;
      }

      // Create subdirectories for different log types
      final appLogDir = Directory('${appDir.path}/logs/app');
      final dataLogDir = Directory('${dataDir.path}/logs/data');

      await appLogDir.create(recursive: true);
      await dataLogDir.create(recursive: true);

      _appLogDirectory = appLogDir.path;
      _dataLogDirectory = dataLogDir.path;

      debugPrint('Log directories initialized:');
      debugPrint('  App logs: $_appLogDirectory');
      debugPrint('  Data logs: $_dataLogDirectory');
    } catch (e) {
      debugPrint('Failed to initialize log directories: $e');
      // Set fallback paths
      _appLogDirectory = './logs/app';
      _dataLogDirectory = './logs/data';
    }
  }

  /// Ensure initialization is complete before using the service
  Future<void> ensureInitialized() async {
    if (_initializeCompleter != null) {
      await _initializeCompleter!.future;
    }
  }

  /// Get platform-agnostic path for app log file
  String getAppLogPath([String? filename]) {
    final name = filename ?? 'app.log';
    return '$_appLogDirectory/$name';
  }

  /// Get platform-agnostic path for data log file
  String getDataLogPath(String loggerName, [String? filename]) {
    final name = filename ?? '$loggerName.tsv';
    return '$_dataLogDirectory/$name';
  }

  static String wrapMessageColor(String message, String levelName) {
    if (!useColors || !stdout.supportsAnsiEscapes) {
      return message;
    }
    // ANSI color codes
    const reset = '\x1B[0m';
    const red = '\x1B[31m';
    const green = '\x1B[32m';
    const yellow = '\x1B[33m';
    const blue = '\x1B[34m';
    const magenta = '\x1B[35m';
    const cyan = '\x1B[36m';

    String color;
    Level level = LogLevelStringExtension.fromName(levelName);
    if (level >= Level.SEVERE) {
      color = red;
    } else if (level >= Level.WARNING) {
      color = yellow;
    } else if (level >= Level.INFO) {
      color = green;
    } else if (level >= Level.CONFIG) {
      color = cyan;
    } else if (level >= Level.FINE) {
      color = blue;
    } else if (level >= Level.FINER) {
      color = magenta;
    } else {
      color = reset; // Default terminal color
    }

    return '$color$message$reset';
  }

  void _initializeLogger() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      final level = record.level;
      if (level >= _minLevel) {
        _addEntry(
          AppLogEntry(
            timestamp: record.time.toIso8601String(),
            level: level.toString(),
            message: record.message,
            logger: record.loggerName,
          ),
        );
      }
    });
  }

  void _setupPeriodicAppFlush() {
    _appFlushTimer = Timer.periodic(_flushInterval, (_) async {
      await _flushAppBuffer();
    });
  }

  void _addEntry(LogEntry entry) {
    _controller.add(entry);

    if (entry is AppLogEntry) {
      // Handle console output for app logs
      if (_appLogDestination == LogDestination.console ||
          _appLogDestination == LogDestination.both) {
        if (kDebugMode) {
          debugPrint(wrapMessageColor(entry.format(), entry.level));
        }
      }

      // Handle file output for app logs
      if ((_appLogDestination == LogDestination.file ||
              _appLogDestination == LogDestination.both) &&
          _isAppFileLoggingEnabled) {
        bool shouldFlush = false;
        unawaited(
          _appBufferLock.synchronized(() {
            _appBuffer.add(entry);
            if (_appBuffer.length >= _bufferSize && !_appFlushPending) {
              _appFlushPending = true;
              shouldFlush = true;
            }

            if (shouldFlush) {
              unawaited(
                _flushAppBuffer().whenComplete(() => _appFlushPending = false),
              );
            }
          }),
        );
      }
    }
  }

  /// Flush the app log buffer to the file isolate
  Future<void> _flushAppBuffer({bool ignore = false}) async {
    if (!_isAppFileLoggingEnabled && !ignore) {
      return;
    }

    await _appBufferLock.synchronized(() async {
      while (_appBuffer.isNotEmpty) {
        final entry = _appBuffer.removeFirst();
        _appFileSendPort!.send(entry);
      }
    });
  }

  /// Enable app logging to file
  Future<void> enableAppFileLogging({String? customPath}) async {
    if (_isAppFileLoggingEnabled) return;

    // Ensure directories are initialized first
    await ensureInitialized();

    try {
      // Use platform-agnostic path if no custom path provided
      _logFilePath = customPath ?? getAppLogPath();

      final receivePort = ReceivePort();
      _appFileIsolate = await Isolate.spawn(_fileLoggingIsolate, [
        receivePort.sendPort,
        _logFilePath!,
        'app', // formatter type
      ]);

      _isolateCompleter = Completer<void>();

      _appLogHandlerSubscription = receivePort.listen((message) async {
        if (message is SendPort) {
          _appFileSendPort = message;
          _isAppFileLoggingEnabled = true;
          _setupPeriodicAppFlush();
          _isolateCompleter?.complete();
        } else if (message is ExitedMessage) {
          _appFileIsolate = null;
          _appFileSendPort = null;
          _isAppFileLoggingEnabled = false;
          _isolateCompleter?.complete();
          _appLogHandlerSubscription?.cancel();
          _appLogHandlerSubscription = null;
        }
      });
      await _isolateCompleter?.future.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Timeout waiting for app logging isolate to start');
          try {
            _appFileIsolate?.kill(priority: Isolate.immediate);
          } catch (e) {
            debugPrint('Failed to kill app logging isolate: $e');
          }
          return;
        },
      );
      _isolateCompleter = null;
    } catch (e) {
      debugPrint('Failed to enable app file logging: $e');
    }
  }

  Future<void> disableAppFileLogging() async {
    if (!_isAppFileLoggingEnabled) return;

    debugPrint('Disabling app file logging...');

    // Cancel the flush timer first
    _appFlushTimer?.cancel();
    _appFlushTimer = null;

    // Final flush of any pending data (bypass lock to avoid deadlock)
    try {
      debugPrint('Attempting final app buffer flush...');
      // Don't use synchronized here to avoid deadlock - just send remaining entries
      while (_appBuffer.isNotEmpty) {
        final entry = _appBuffer.removeFirst();
        _appFileSendPort?.send(entry);
      }
      debugPrint('Final app buffer flush completed');
    } catch (e) {
      debugPrint('Error during final app buffer flush: $e');
    }

    // Set up completer for isolate exit
    _isolateCompleter = Completer<void>();

    // Send stop message to isolate
    debugPrint('Sending stop message to app file isolate');
    _appFileSendPort?.send(const StopMessage());

    // Wait for isolate to exit gracefully
    try {
      await _isolateCompleter?.future.timeout(
        Duration(seconds: 3),
        onTimeout: () {
          debugPrint('Timeout waiting for app logging isolate to exit');
          return;
        },
      );
      debugPrint('App logging isolate exited gracefully');
    } catch (e) {
      debugPrint('Error waiting for app logging isolate exit: $e');
    }

    // Force kill if still running
    try {
      _appFileIsolate?.kill(priority: Isolate.immediate);
    } catch (e) {
      debugPrint('Error killing app logging isolate: $e');
    }

    // Clean up all references
    _isAppFileLoggingEnabled = false;
    _appLogHandlerSubscription?.cancel();
    _appLogHandlerSubscription = null;
    _isolateCompleter = null;
    _appFileIsolate = null;
    _appFileSendPort = null;

    debugPrint('App file logging disabled');
  }

  /// Enable a specific file logger
  Future<void> _enableFileLogger(FileLogger logger, String filePath) async {
    try {
      logger._receivePort = ReceivePort();
      logger._isolate = await Isolate.spawn(_fileLoggingIsolate, [
        logger._receivePort!.sendPort,
        filePath,
        logger.formatterType,
      ]);

      final completer = Completer<void>();

      logger._subscription = logger._receivePort!.listen((message) async {
        if (message is SendPort) {
          logger._sendPort = message;

          // Set up periodic timer for this specific logger
          logger._flushTimer = Timer.periodic(_flushInterval, (_) async {
            // Reset flush pending in case it got stuck
            logger._flushPending = false;
            await _flushFileLogger(logger);
          });

          completer.complete();
        } else if (message is ExitedMessage) {
          logger.cleanup();
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      });

      await completer.future.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Timeout waiting for ${logger.name} isolate to start');
          logger.cleanup();
          return;
        },
      );
    } catch (e) {
      debugPrint('Failed to enable file logger ${logger.name}: $e');
      logger.cleanup();
    }
  }

  /// Flush a specific file logger buffer
  Future<void> _flushFileLogger(FileLogger logger) async {
    if (!logger.isEnabled) {
      return;
    }

    try {
      await logger._bufferLock.synchronized(() async {
        while (logger._buffer.isNotEmpty) {
          final entry = logger._buffer.removeFirst();
          logger._sendPort!.send(entry);
        }
      });
    } catch (e) {
      debugPrint('Error flushing file logger ${logger.name}: $e');
    }
  }

  static void _fileLoggingIsolate(List<dynamic> args) async {
    final SendPort mainSendPort = args[0];
    final String logFilePath = args[1];
    final String formatterType = args[2];

    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    IOSink? logFile;
    File? file;
    bool shouldExit = false;

    // Get the formatter function
    final formatter = LoggerFormatterFactory.getFormatter(formatterType);

    try {
      file = File(logFilePath);
      await file.parent.create(recursive: true);
      logFile = file.openWrite(mode: FileMode.append);
    } catch (e) {
      debugPrint('File logging isolate error: $e');
      Isolate.exit(mainSendPort, const ExitedMessage());
    }

    int lineCount = 0;

    await for (final data in receivePort) {
      try {
        if (data is LogEntry) {
          if (!shouldExit) {
            final formatted = formatter(data);

            logFile.writeln(formatted);

            if (lineCount >= _logFlushLines) {
              await logFile.flush();
              lineCount = 0;
            }
          }
        } else if (data is StopMessage) {
          shouldExit = true;
          break;
        } else {}
      } catch (e) {
        debugPrint('File logging isolate error processing message: $e');
        break;
      }
    }

    // Clean shutdown
    try {
      await logFile.flush();
      await logFile.close();
    } catch (e) {
      debugPrint('File logging isolate error during shutdown: $e');
    } finally {
      logFile = null;
      receivePort.close();
      Isolate.exit(mainSendPort, const ExitedMessage());
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

  /// Configure app logging destination (console, file, or both)
  Future<void> configureAppLogging({
    LogDestination destination = LogDestination.console,
    String? filePath,
  }) async {
    _appLogDestination = destination;
    if (destination == LogDestination.file ||
        destination == LogDestination.both) {
      await enableAppFileLogging(customPath: filePath);
    }
  }

  /// Create a high-frequency file logger (no console output)
  Future<void> createFileLogger(
    String name, {
    String? filePath,
    String format = 'tsv', // tsv, csv
  }) async {
    // Ensure directories are initialized first
    await ensureInitialized();

    final logger = FileLogger(name: name, formatterType: format);
    _fileLoggers[name] = logger;

    // Use platform-agnostic path if no custom path provided
    final path = filePath ?? getDataLogPath(name);
    await _enableFileLogger(logger, path);
  }

  /// Create a data logger with platform-agnostic path
  Future<void> createDataLogger(String name, {String format = 'tsv'}) async {
    await createFileLogger(name, format: format);
  }

  /// Initialize complete logging system with app and data logging
  Future<void> initializeCompleteLogging({
    LogDestination appLogDestination = LogDestination.both,
    List<String> dataLoggers = const [],
    String dataLogFormat = 'tsv',
  }) async {
    try {
      // Ensure base initialization is complete first
      await ensureInitialized();

      // Configure app logging
      await configureAppLogging(destination: appLogDestination);

      // Create data loggers
      for (final loggerName in dataLoggers) {
        await createDataLogger(loggerName, format: dataLogFormat);
      }

      info('Complete logging system initialized', logger: 'LogService');
      info('App logs: ${getAppLogPath()}', logger: 'LogService');
      if (dataLoggers.isNotEmpty) {
        info(
          'Data loggers created: ${dataLoggers.join(", ")}',
          logger: 'LogService',
        );
      }
    } catch (e) {
      severe(
        'Failed to initialize complete logging system: $e',
        logger: 'LogService',
      );
    }
  }

  /// Get current logging status and paths
  Map<String, dynamic> getLoggingStatus() {
    return {
      'appLogging': {
        'enabled': _isAppFileLoggingEnabled,
        'destination': _appLogDestination.toString(),
        'path': _logFilePath,
      },
      'dataLoggers': _fileLoggers.keys.toList(),
      'directories': {
        'appLogDirectory': _appLogDirectory,
        'dataLogDirectory': _dataLogDirectory,
      },
    };
  }

  /// Log high-frequency data to a specific file logger (bypasses console)
  void logData(
    String loggerName,
    String message, {
    Map<String, dynamic> data = const {},
    DateTime? timestamp,
  }) {
    final logger = _fileLoggers[loggerName];
    if (logger == null) {
      // Fallback to app log if logger doesn't exist
      warning('File logger "$loggerName" not found, logging to app log');
      info('$loggerName: $message');
      return;
    }

    // Convert data map to string format for TSV/CSV
    final dataEntries = data.entries
        .map((e) => '${e.key}:${e.value}')
        .join('\t');

    final entry = DataLogEntry(
      timestamp: (timestamp ?? DateTime.now()).toIso8601String(),
      message: message,
      dataString: dataEntries,
    );

    // Add to logger's buffer and flush if needed
    if (logger.isEnabled) {
      logger._buffer.add(entry);

      // Flush if buffer is getting full (without synchronization for now)
      if (logger._buffer.length >= _bufferSize) {
        if (!logger._flushPending) {
          logger._flushPending = true;
          unawaited(
            _flushFileLogger(
              logger,
            ).whenComplete(() => logger._flushPending = false),
          );
        } else {}
      }
    }

    _controller.add(entry);
  }

  Future<void> dispose() async {
    debugPrint('Starting LogService disposal...');

    // Disable app logging first
    try {
      await disableAppFileLogging();
      debugPrint('App file logging disabled');
    } catch (e) {
      debugPrint('Error disabling app file logging: $e');
    }

    // Flush all file logger buffers immediately (bypass locks to avoid deadlock)
    debugPrint('Flushing ${_fileLoggers.length} file logger buffers...');
    for (final logger in _fileLoggers.values) {
      if (logger.isEnabled) {
        try {
          // Bypass the synchronized lock and flush directly
          while (logger._buffer.isNotEmpty) {
            final entry = logger._buffer.removeFirst();
            logger._sendPort?.send(entry);
          }
          debugPrint('Flushed buffer for logger ${logger.name}');
        } catch (e) {
          debugPrint('Error flushing logger ${logger.name}: $e');
        }
      }
    }

    // Send stop messages to all isolates after flushing
    debugPrint('Sending stop messages to file loggers...');
    for (final logger in _fileLoggers.values) {
      if (logger.isEnabled) {
        logger._sendPort?.send(const StopMessage());
      }
    }

    // Give isolates time to write the flushed data and shut down
    debugPrint('Waiting for isolates to process data and shut down...');
    await Future.delayed(Duration(milliseconds: 500));

    // Force cleanup all file loggers
    debugPrint('Force cleaning up all file loggers');
    for (final logger in _fileLoggers.values) {
      try {
        logger.cleanup();
      } catch (e) {
        debugPrint('Error cleaning up logger ${logger.name}: $e');
      }
    }
    _fileLoggers.clear();

    debugPrint('LogService disposed successfully');
  }
}
