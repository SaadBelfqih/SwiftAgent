// By Dennis Müller

import Foundation
import SwiftAgent

@main
struct AgentRecorderCLI {
  static func main() async {
    SwiftAgentConfiguration.setLoggingEnabled(false)
    SwiftAgentConfiguration.setNetworkLoggingEnabled(false)

    await AgentRecorderApp().run()
  }
}
