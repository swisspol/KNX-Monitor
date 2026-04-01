import 'package:logging/logging.dart';

final log = Logger('KNX');

/// All log records captured since app start.
final List<LogRecord> logHistory = [];

/// Initialize logging. Call once at app startup.
void initLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    logHistory.add(record);
    if (logHistory.length > 1000) {
      logHistory.removeAt(0);
    }
  });
}
