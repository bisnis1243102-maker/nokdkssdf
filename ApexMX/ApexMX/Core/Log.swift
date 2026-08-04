import Foundation
import os

/// Structured logging built on `os.Logger`.
///
/// Using the unified logging system rather than `print` means log output is
/// filterable by category and severity in Console and in sysdiagnose captures,
/// costs nothing when nobody is listening, and never leaks to release builds
/// unless deliberately marked public.
public enum Log {

    public enum Category: String {
        case app, physics, gameplay, rendering, audio, input, save, network, performance

        fileprivate var logger: Logger {
            Logger(subsystem: Log.subsystem, category: rawValue)
        }
    }

    private static let subsystem = "com.apexmx.game"

    public static func debug(_ message: String, category: Category = .app) {
        #if DEBUG
        category.logger.debug("\(message, privacy: .public)")
        #endif
    }

    public static func info(_ message: String, category: Category = .app) {
        category.logger.info("\(message, privacy: .public)")
    }

    public static func warning(_ message: String, category: Category = .app) {
        category.logger.warning("\(message, privacy: .public)")
    }

    public static func error(_ message: String, category: Category = .app) {
        category.logger.error("\(message, privacy: .public)")
    }

    public static func critical(_ message: String, category: Category = .app) {
        category.logger.critical("\(message, privacy: .public)")
    }
}
