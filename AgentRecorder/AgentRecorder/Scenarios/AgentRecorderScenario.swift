// By Dennis Müller

import SwiftAgent

struct AgentRecorderScenario: Sendable {
  var id: String
  var provider: Provider
  var unitTestFile: String
  var expectedRecordedResponsesCount: Int

  var run: @Sendable (HTTPReplayRecorder, AgentRecorderSecrets) async throws -> Void

  func callAsFunction(
    recorder: HTTPReplayRecorder,
    secrets: AgentRecorderSecrets,
  ) async throws {
    try await run(recorder, secrets)
  }
}
