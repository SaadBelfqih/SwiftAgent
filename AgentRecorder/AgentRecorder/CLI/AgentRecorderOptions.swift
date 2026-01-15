// By Dennis Müller

struct AgentRecorderOptions: Sendable {
  var provider: Provider = .both
  var scenario: String?
  var secretsPlistPath: String?
  var includeRequests: Bool = false
  var includeHeaders: Bool = true
  var prettyPrintJSON: Bool = true

  var showHelp: Bool = false
  var listScenarios: Bool = false

  static func parse(_ argv: [String]) throws -> AgentRecorderOptions {
    var options = AgentRecorderOptions()

    var iterator = argv.dropFirst().makeIterator()
    while let arg = iterator.next() {
      switch arg {
      case "--help", "-h":
        options.showHelp = true
      case "--list-scenarios":
        options.listScenarios = true
      case "--provider":
        let value = iterator.next() ?? ""
        guard let provider = Provider(rawValue: value.lowercased()) else {
          throw AgentRecorderError.invalidArgument("--provider \(value)")
        }

        options.provider = provider
      case "--scenario":
        let value = iterator.next() ?? ""
        guard value.isEmpty == false else {
          throw AgentRecorderError.invalidArgument("--scenario <name>")
        }

        options.scenario = value
      case "--secrets-plist":
        let value = iterator.next() ?? ""
        guard value.isEmpty == false else {
          throw AgentRecorderError.invalidArgument("--secrets-plist <path>")
        }

        options.secretsPlistPath = value
      case "--include-requests":
        options.includeRequests = true
      case "--include-headers":
        options.includeHeaders = true
      case "--no-include-headers":
        options.includeHeaders = false
      case "--pretty-print-json":
        options.prettyPrintJSON = true
      case "--no-pretty-print-json":
        options.prettyPrintJSON = false
      default:
        throw AgentRecorderError.invalidArgument(arg)
      }
    }

    return options
  }

  static let helpText: String = """
  AgentRecorder — record real provider HTTP back-and-forth and print paste-ready Swift fixtures.

  Usage:
    AgentRecorder [--provider openai|anthropic|both] [--scenario <name>] [--secrets-plist <path>] [--include-requests] [--no-include-headers] [--no-pretty-print-json]
    AgentRecorder --list-scenarios
    AgentRecorder --help

  Environment:
    OPENAI_API_KEY       Required for OpenAI scenarios unless using a Secrets.plist.
    ANTHROPIC_API_KEY    Required for Anthropic scenarios unless using a Secrets.plist.
    AGENT_RECORDER_SECRETS_PLIST  Optional path to Secrets.plist (fallback if API key env vars are missing).

  Output:
    Prints Swift raw-string fixtures to stdout. (Xcode: appears in the Debug console.)
  """
}
