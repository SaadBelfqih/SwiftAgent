// By Dennis Müller

import Foundation

enum AgentRecorderError: LocalizedError {
  case missingAPIKey(environmentKey: String, secretsPlistKey: String)
  case invalidArgument(String)
  case unknownScenario(String)
  case timedOutWaitingForRecording

  var errorDescription: String? {
    switch self {
    case let .missingAPIKey(environmentKey, secretsPlistKey):
      "Missing API key. Set \(environmentKey) or provide \(secretsPlistKey) in Secrets.plist."
    case let .invalidArgument(argument):
      "Invalid argument: \(argument)"
    case let .unknownScenario(name):
      "Unknown scenario: \(name)"
    case .timedOutWaitingForRecording:
      "Timed out while waiting for the stream recorder to finish capturing the response."
    }
  }
}
