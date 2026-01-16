//
// PaydirtLogger.swift
// Logging utility for Paydirt SDK
//

import Foundation
import OSLog

public enum PaydirtLogLevel: CaseIterable {
    case none
    case error
    case warning
    case info
    case debug
}

public class PaydirtLogger {
    static let shared = PaydirtLogger()

    private var currentLevel: PaydirtLogLevel = .none
    private let logger = Logger(subsystem: "ai.paydirt.sdk", category: "Paydirt")

    private init() {}

    func setLogLevel(_ level: PaydirtLogLevel) {
        currentLevel = level
        if level != .none {
            info("Logger", "Log level set to \(level)")
        }
    }

    func debug(_ category: String, _ message: String) {
        guard currentLevel == .debug else { return }
        logger.debug("[\(category)] \(message)")
    }

    func info(_ category: String, _ message: String) {
        guard currentLevel == .info || currentLevel == .debug else { return }
        logger.info("[\(category)] \(message)")
    }

    func warning(_ category: String, _ message: String) {
        guard currentLevel == .warning || currentLevel == .info || currentLevel == .debug else { return }
        logger.warning("[\(category)] \(message)")
    }

    func error(_ category: String, _ message: String) {
        guard currentLevel != .none else { return }
        logger.error("[\(category)] \(message)")
    }
}
