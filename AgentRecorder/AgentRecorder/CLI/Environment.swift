// By Dennis Müller

import Foundation

enum Environment {
  static func value(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
