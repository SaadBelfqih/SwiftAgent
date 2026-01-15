// By Dennis Müller

import Foundation
import SwiftAgent

enum RecorderWaiter {
  static func waitForRecordedResponses(
    expectedCount: Int,
    recorder: HTTPReplayRecorder,
    timeout: Duration = .seconds(2),
  ) async throws {
    let deadline = ContinuousClock().now.advanced(by: timeout)

    while ContinuousClock().now < deadline {
      try Task.checkCancellation()

      let recorded = await recorder.recordedResponses()
      if recorded.count >= expectedCount {
        return
      }

      try await Task.sleep(for: .milliseconds(50))
    }

    throw AgentRecorderError.timedOutWaitingForRecording
  }
}
