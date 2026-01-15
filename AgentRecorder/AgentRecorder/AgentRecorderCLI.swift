// By Dennis Müller

import AnthropicSession
import Darwin
import Foundation
import FoundationModels
import OpenAI
import OpenAISession
import SwiftAgent
import SwiftAnthropic

@main
struct AgentRecorderCLI {
  static func main() async {
    SwiftAgentConfiguration.setLoggingEnabled(false)
    SwiftAgentConfiguration.setNetworkLoggingEnabled(false)

    do {
      let options = try Options.parse(CommandLine.arguments)

      if options.showHelp {
        print(Options.helpText)
        return
      }

      if options.listScenarios {
        print(Scenario.helpText)
        return
      }

      try await run(options: options)
    } catch {
      Stderr.print("error: \(error.localizedDescription)")
      Stderr.print("")
      Stderr.print(Options.helpText)
      exit(1)
    }
  }

  private static func run(options: Options) async throws {
    let recorder = HTTPReplayRecorder(
      options: .init(
        includeRequests: options.includeRequests,
        includeHeaders: options.includeHeaders,
        prettyPrintJSON: options.prettyPrintJSON,
      ),
    )

    if let scenario = options.scenario {
      try await scenario.run(
        with: recorder,
        secretsPlistPath: options.secretsPlistPath,
      )
      try await RecorderWaiter.waitForRecordedResponses(
        scenario: scenario,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet())
      return
    }

    switch options.provider {
    case .openAI:
      try await Scenario.toolCallWeatherOpenAI.run(
        with: recorder,
        secretsPlistPath: options.secretsPlistPath,
      )
      try await RecorderWaiter.waitForRecordedResponses(
        scenario: .toolCallWeatherOpenAI,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet())
    case .anthropic:
      try await Scenario.toolCallWeatherAnthropic.run(
        with: recorder,
        secretsPlistPath: options.secretsPlistPath,
      )
      try await RecorderWaiter.waitForRecordedResponses(
        scenario: .toolCallWeatherAnthropic,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet())
    case .both:
      try await Scenario.toolCallWeatherOpenAI.run(
        with: recorder,
        secretsPlistPath: options.secretsPlistPath,
      )
      try await RecorderWaiter.waitForRecordedResponses(
        scenario: .toolCallWeatherOpenAI,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet(responseNamePrefix: "openAIResponse"))

      await recorder.reset()

      try await Scenario.toolCallWeatherAnthropic.run(
        with: recorder,
        secretsPlistPath: options.secretsPlistPath,
      )
      print("")
      try await RecorderWaiter.waitForRecordedResponses(
        scenario: .toolCallWeatherAnthropic,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet(responseNamePrefix: "anthropicResponse"))
    }
  }
}

private enum Provider: String {
  case openAI = "openai"
  case anthropic
  case both
}

private struct Options {
  var provider: Provider = .both
  var scenario: Scenario?
  var secretsPlistPath: String?
  var includeRequests: Bool = false
  var includeHeaders: Bool = true
  var prettyPrintJSON: Bool = true

  var showHelp: Bool = false
  var listScenarios: Bool = false

  static func parse(_ argv: [String]) throws -> Options {
    var options = Options()

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
          throw CLIError.invalidArgument("--provider \(value)")
        }

        options.provider = provider
      case "--scenario":
        let value = iterator.next() ?? ""
        guard let scenario = Scenario(rawValue: value.lowercased()) else {
          throw CLIError.invalidArgument("--scenario \(value)")
        }

        options.scenario = scenario
      case "--secrets-plist":
        let value = iterator.next() ?? ""
        guard value.isEmpty == false else {
          throw CLIError.invalidArgument("--secrets-plist <path>")
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
        throw CLIError.invalidArgument(arg)
      }
    }

    return options
  }

  static let helpText: String = """
  AgentRecorder — record real provider HTTP responses and print paste-ready Swift fixtures.

  Usage:
    AgentRecorder [--provider openai|anthropic|both] [--scenario <name>] [--secrets-plist <path>] [--include-requests] [--no-include-headers] [--no-pretty-print-json]
    AgentRecorder --list-scenarios
    AgentRecorder --help

  Environment:
    OPENAI_API_KEY       Required for --provider openai|both
    ANTHROPIC_API_KEY    Required for --provider anthropic|both
    AGENT_RECORDER_SECRETS_PLIST  Optional path to Secrets.plist (fallback if API key env vars are missing)

  Output:
    Prints Swift raw-string fixtures to stdout. (Xcode: appears in the Debug console.)
  """
}

private enum Scenario: String, CaseIterable {
  case toolCallWeatherOpenAI = "tool-call-weather-openai"
  case toolCallWeatherAnthropic = "tool-call-weather-anthropic"
  case anthropicText = "anthropic-text"
  case anthropicStreamingText = "anthropic-streaming-text"
  case anthropicStructuredOutput = "anthropic-structured-output"
  case anthropicToolCallPing = "anthropic-tool-call-ping"

  var expectedRecordedResponsesCount: Int {
    switch self {
    case .toolCallWeatherOpenAI:
      2
    case .toolCallWeatherAnthropic:
      2
    case .anthropicText:
      1
    case .anthropicStreamingText:
      1
    case .anthropicStructuredOutput:
      1
    case .anthropicToolCallPing:
      2
    }
  }

  static let helpText: String = """
  Scenarios:
    \(Scenario.toolCallWeatherOpenAI.rawValue)
    \(Scenario.toolCallWeatherAnthropic.rawValue)
    \(Scenario.anthropicText.rawValue)
    \(Scenario.anthropicStreamingText.rawValue)
    \(Scenario.anthropicStructuredOutput.rawValue)
    \(Scenario.anthropicToolCallPing.rawValue)
  """

  func run(
    with recorder: HTTPReplayRecorder,
    secretsPlistPath: String?,
  ) async throws {
    switch self {
    case .toolCallWeatherOpenAI:
      try await runOpenAI(
        recorder: recorder,
        secretsPlistPath: secretsPlistPath,
      )
    case .toolCallWeatherAnthropic:
      try await runAnthropic(
        recorder: recorder,
        secretsPlistPath: secretsPlistPath,
      )
    case .anthropicText:
      try await runAnthropicText(
        recorder: recorder,
        secretsPlistPath: secretsPlistPath,
      )
    case .anthropicStreamingText:
      try await runAnthropicStreamingText(
        recorder: recorder,
        secretsPlistPath: secretsPlistPath,
      )
    case .anthropicStructuredOutput:
      try await runAnthropicStructuredOutput(
        recorder: recorder,
        secretsPlistPath: secretsPlistPath,
      )
    case .anthropicToolCallPing:
      try await runAnthropicToolCallPing(
        recorder: recorder,
        secretsPlistPath: secretsPlistPath,
      )
    }
  }

  private func runOpenAI(
    recorder: HTTPReplayRecorder,
    secretsPlistPath: String?,
  ) async throws {
    let apiKey = try Secrets.apiKey(
      environmentKey: "OPENAI_API_KEY",
      secretsPlistKey: "OpenAI_API_Key_Debug",
      secretsPlistPath: secretsPlistPath,
    )

    let configuration = OpenAIConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = OpenAISession(
      tools: OpenAIWeatherTool(),
      instructions: "Always call `get_weather` exactly once before answering.",
      configuration: configuration,
    )

    let prompt = "What is the weather in New York City, USA?"
    let stream = try session.streamResponse(
      to: prompt,
      options: .init(include: [.reasoning_encryptedContent]),
    )

    for try await _ in stream {}
  }

  private func runAnthropic(
    recorder: HTTPReplayRecorder,
    secretsPlistPath: String?,
  ) async throws {
    let apiKey = try Secrets.apiKey(
      environmentKey: "ANTHROPIC_API_KEY",
      secretsPlistKey: "Anthropic_API_Key_Debug",
      secretsPlistPath: secretsPlistPath,
    )

    let configuration = AnthropicConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = AnthropicSession(
      tools: AnthropicWeatherTool(),
      instructions: """
      Do not write any text before the tool call.
      Call `get_weather` exactly once with:
      { "location": "Tokyo", "requestedDate": "2026-01-15", "timeOfDay": "afternoon" }
      After tool output, reply with exactly: Done.
      """,
      configuration: configuration,
    )

    let stream = try session.streamResponse(
      to: "Weather update",
      using: .claude37SonnetLatest,
    )

    for try await _ in stream {}
  }

  private func runAnthropicText(
    recorder: HTTPReplayRecorder,
    secretsPlistPath: String?,
  ) async throws {
    let apiKey = try Secrets.apiKey(
      environmentKey: "ANTHROPIC_API_KEY",
      secretsPlistKey: "Anthropic_API_Key_Debug",
      secretsPlistPath: secretsPlistPath,
    )

    let configuration = AnthropicConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = AnthropicSession(
      schema: RecordingEmptySchema(),
      instructions: "Reply with exactly: Hello from Claude",
      configuration: configuration,
    )

    _ = try await session.respond(
      to: "Hello?",
      using: .claude37SonnetLatest,
    )
  }

  private func runAnthropicStreamingText(
    recorder: HTTPReplayRecorder,
    secretsPlistPath: String?,
  ) async throws {
    let apiKey = try Secrets.apiKey(
      environmentKey: "ANTHROPIC_API_KEY",
      secretsPlistKey: "Anthropic_API_Key_Debug",
      secretsPlistPath: secretsPlistPath,
    )

    let configuration = AnthropicConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = AnthropicSession(
      schema: RecordingEmptySchema(),
      instructions: "",
      configuration: configuration,
    )

    let stream = try session.streamResponse(
      to: "Reply with exactly: Hello",
      using: .claude37SonnetLatest,
    )

    for try await _ in stream {}
  }

  private func runAnthropicStructuredOutput(
    recorder: HTTPReplayRecorder,
    secretsPlistPath: String?,
  ) async throws {
    let apiKey = try Secrets.apiKey(
      environmentKey: "ANTHROPIC_API_KEY",
      secretsPlistKey: "Anthropic_API_Key_Debug",
      secretsPlistPath: secretsPlistPath,
    )

    let configuration = AnthropicConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = AnthropicSession(
      schema: RecordingStructuredOutputSchema(),
      instructions: "Return temperature=21 and condition=Sunny.",
      configuration: configuration,
    )

    _ = try await session.respond(
      to: "Weather update",
      generating: RecordingWeatherReport.self,
      using: .claude37SonnetLatest,
    )
  }

  private func runAnthropicToolCallPing(
    recorder: HTTPReplayRecorder,
    secretsPlistPath: String?,
  ) async throws {
    let apiKey = try Secrets.apiKey(
      environmentKey: "ANTHROPIC_API_KEY",
      secretsPlistKey: "Anthropic_API_Key_Debug",
      secretsPlistPath: secretsPlistPath,
    )

    let configuration = AnthropicConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = AnthropicSession(
      schema: RecordingPingSchema(),
      instructions: """
      Do not write any text before the tool call.
      Call `ping` exactly once with empty JSON {}.
      After tool output, reply with exactly: pong
      """,
      configuration: configuration,
    )

    let stream = try session.streamResponse(
      to: "Ping",
      using: .claude37SonnetLatest,
    )

    for try await _ in stream {}
  }
}

private enum RecorderWaiter {
  static func waitForRecordedResponses(
    scenario: Scenario,
    recorder: HTTPReplayRecorder,
    timeout: Duration = .seconds(2),
  ) async throws {
    let deadline = ContinuousClock().now.advanced(by: timeout)

    while ContinuousClock().now < deadline {
      try Task.checkCancellation()

      let recorded = await recorder.recordedResponses()
      if recorded.count >= scenario.expectedRecordedResponsesCount {
        return
      }

      try await Task.sleep(for: .milliseconds(50))
    }

    throw CLIError.timedOutWaitingForRecording
  }
}

private struct OpenAIWeatherTool: FoundationModels.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

private struct AnthropicWeatherTool: FoundationModels.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
    var requestedDate: String
    var timeOfDay: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

@SessionSchema
private struct RecordingEmptySchema {}

@SessionSchema
private struct RecordingStructuredOutputSchema {
  @StructuredOutput(RecordingWeatherReport.self) var weatherReport
}

private struct RecordingWeatherReport: StructuredOutput {
  static let name: String = "weather_report"

  @Generable
  struct Schema {
    var temperature: Int
    var condition: String
  }
}

@SessionSchema
private struct RecordingPingSchema {
  @Tool var ping = RecordingPingTool()
}

private struct RecordingPingTool: FoundationModels.Tool {
  var name: String = "ping"
  var description: String = "Returns pong with no arguments."

  @Generable
  struct Arguments {
    init() {}
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "pong"
  }
}

private enum Environment {
  static func value(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private enum Secrets {
  static func apiKey(
    environmentKey: String,
    secretsPlistKey: String,
    secretsPlistPath: String?,
  ) throws -> String {
    if let envValue = Environment.value(environmentKey), envValue.isEmpty == false {
      return envValue
    }

    let resolvedPlistURL = resolveSecretsPlistURL(
      overridePath: secretsPlistPath,
    )

    if let resolvedPlistURL, let plistValue = loadPlistValue(url: resolvedPlistURL, key: secretsPlistKey) {
      return plistValue
    }

    throw CLIError.missingAPIKey(
      environmentKey: environmentKey,
      secretsPlistKey: secretsPlistKey,
    )
  }

  private static func resolveSecretsPlistURL(overridePath: String?) -> URL? {
    if let overridePath {
      let url = urlFromUserPath(overridePath)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }

    if let envPath = Environment.value("AGENT_RECORDER_SECRETS_PLIST"), envPath.isEmpty == false {
      let url = urlFromUserPath(envPath)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }

    return nil
  }

  private static func urlFromUserPath(_ path: String) -> URL {
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }

    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return base.appendingPathComponent(path)
  }

  private static func loadPlistValue(url: URL, key: String) -> String? {
    do {
      let data = try Data(contentsOf: url)
      let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil,
      )

      guard let dict = plist as? [String: Any] else {
        return nil
      }

      let value = dict[key] as? String
      return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }
}

private enum Stderr {
  static func print(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}

private enum CLIError: LocalizedError {
  case missingEnvironmentVariable(String)
  case missingAPIKey(environmentKey: String, secretsPlistKey: String)
  case invalidArgument(String)
  case timedOutWaitingForRecording

  var errorDescription: String? {
    switch self {
    case let .missingEnvironmentVariable(key):
      "Missing required environment variable: \(key)"
    case let .missingAPIKey(environmentKey, secretsPlistKey):
      "Missing API key. Set \(environmentKey) or provide \(secretsPlistKey) in Secrets.plist."
    case let .invalidArgument(argument):
      "Invalid argument: \(argument)"
    case .timedOutWaitingForRecording:
      "Timed out while waiting for the stream recorder to finish capturing the response."
    }
  }
}

private extension OpenAIConfiguration {
  static func recording(
    apiKey: String,
    recorder: HTTPReplayRecorder,
  ) -> OpenAIConfiguration {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let decoder = JSONDecoder()

    var interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      },
      onUnauthorized: { _, _, _ in
        false
      },
    )
    interceptors = interceptors.recording(to: recorder)

    let configuration = HTTPClientConfiguration(
      baseURL: URL(string: "https://api.openai.com")!,
      defaultHeaders: [:],
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    let session = RecordingURLSession.make(timeout: configuration.timeout)
    return OpenAIConfiguration(httpClient: URLSessionHTTPClient(configuration: configuration, session: session))
  }
}

private extension AnthropicConfiguration {
  static func recording(
    apiKey: String,
    apiVersion: String = "2023-06-01",
    recorder: HTTPReplayRecorder,
  ) -> AnthropicConfiguration {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let defaultHeaders: [String: String] = [
      "anthropic-version": apiVersion,
    ]

    var interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
      },
      onUnauthorized: { _, _, _ in
        false
      },
    )
    interceptors = interceptors.recording(to: recorder)

    let configuration = HTTPClientConfiguration(
      baseURL: URL(string: "https://api.anthropic.com")!,
      defaultHeaders: defaultHeaders,
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    let session = RecordingURLSession.make(timeout: configuration.timeout)
    return AnthropicConfiguration(httpClient: URLSessionHTTPClient(configuration: configuration, session: session))
  }
}

private enum RecordingURLSession {
  static func make(timeout: TimeInterval) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    return URLSession(configuration: configuration)
  }
}
