// By Dennis Müller

import Darwin
import Foundation
import SwiftAgent

struct AgentRecorderApp {
  func run() async {
    var recorder: HTTPReplayRecorder?

    do {
      let options = try AgentRecorderOptions.parse(CommandLine.arguments)

      if options.showHelp {
        print(AgentRecorderOptions.helpText)
        return
      }

      if options.listScenarios {
        print(ScenarioCatalog.helpText)
        return
      }

      let recorderInstance = HTTPReplayRecorder(
        options: .init(
          includeRequests: options.includeRequests,
          includeHeaders: options.includeHeaders,
          prettyPrintJSON: options.prettyPrintJSON,
        ),
      )
      recorder = recorderInstance

      let secrets = AgentRecorderSecrets(secretsPlistPath: options.secretsPlistPath)

      try await run(
        options: options,
        recorder: recorderInstance,
        secrets: secrets,
      )
    } catch {
      if let recorder, await recorder.recordedResponses().isEmpty == false {
        print("// MARK: - Partial Recording (Scenario Failed)")
        print("")
        await print(recorder.swiftFixtureSnippet())
      }

      Stderr.print("error: \(error.localizedDescription)")
      Stderr.print("")
      Stderr.print(AgentRecorderOptions.helpText)
      exit(1)
    }
  }

  private func run(
    options: AgentRecorderOptions,
    recorder: HTTPReplayRecorder,
    secrets: AgentRecorderSecrets,
  ) async throws {
    if let scenarioID = options.scenario {
      let scenario = try ScenarioCatalog.requireScenario(id: scenarioID)
      try await scenario(recorder: recorder, secrets: secrets)
      try await RecorderWaiter.waitForRecordedResponses(
        expectedCount: scenario.expectedRecordedResponsesCount,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet())
      return
    }

    switch options.provider {
    case .openAI:
      let scenario = ScenarioCatalog.defaultOpenAIScenario
      try await scenario(recorder: recorder, secrets: secrets)
      try await RecorderWaiter.waitForRecordedResponses(
        expectedCount: scenario.expectedRecordedResponsesCount,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet())
    case .anthropic:
      let scenario = ScenarioCatalog.defaultAnthropicScenario
      try await scenario(recorder: recorder, secrets: secrets)
      try await RecorderWaiter.waitForRecordedResponses(
        expectedCount: scenario.expectedRecordedResponsesCount,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet())
    case .both:
      let openAIScenario = ScenarioCatalog.defaultOpenAIScenario
      try await openAIScenario(recorder: recorder, secrets: secrets)
      try await RecorderWaiter.waitForRecordedResponses(
        expectedCount: openAIScenario.expectedRecordedResponsesCount,
        recorder: recorder,
      )
      await print(recorder.swiftFixtureSnippet(responseNamePrefix: "openAIResponse"))

      await recorder.reset()

      let anthropicScenario = ScenarioCatalog.defaultAnthropicScenario
      try await anthropicScenario(recorder: recorder, secrets: secrets)
      try await RecorderWaiter.waitForRecordedResponses(
        expectedCount: anthropicScenario.expectedRecordedResponsesCount,
        recorder: recorder,
      )

      print("")
      await print(recorder.swiftFixtureSnippet(responseNamePrefix: "anthropicResponse"))
    }
  }
}
