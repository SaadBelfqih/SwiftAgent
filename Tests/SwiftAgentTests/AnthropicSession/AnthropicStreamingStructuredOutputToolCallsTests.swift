// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {
  @Tool var weather = WeatherTool()
  @StructuredOutput(WeatherReport.self) var weatherReport
}

@Suite("Anthropic - Streaming - Structured Output - Tool Calls")
struct AnthropicStreamingStructuredOutputToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<MessageParameter>

  init() async {
    mockHTTPClient = ReplayHTTPClient<MessageParameter>(
      recordedResponses: [
        .init(body: streamingToolCallResponse),
        .init(body: streamingStructuredOutputResponse),
      ],
      makeJSONDecoder: {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
      },
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Streams tool calls before emitting structured output")
  func streamsToolsBeforeStructuredOutput() async throws {
    let stream = try session.streamResponse(
      to: "Weather update",
      generating: WeatherReport.self,
      using: .other("claude-haiku-4-5"),
      options: .init(
        maxOutputTokens: 1024,
        minimumStreamingSnapshotInterval: .zero,
      ),
    )

    var generatedTranscript = Transcript()
    var generatedOutputs: [WeatherReport.Schema.PartiallyGenerated] = []

    for try await snapshot in stream {
      generatedTranscript = snapshot.transcript
      if let content = snapshot.content {
        generatedOutputs.append(content)
      }
    }

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
    validateGeneratedOutputs(generatedOutputs)
  }

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 2)
  }

  private func validateTranscript(generatedTranscript: Transcript) throws {
    guard let toolCalls = firstToolCalls(in: generatedTranscript) else {
      Issue.record("Expected tool call entry")
      return
    }

    #expect(toolCalls.calls.count == 1)
    #expect(toolCalls.calls[0].toolName == "get_weather")

    let expectedArguments = try GeneratedContent(json: #"{ "location": "Tokyo" }"#)
    #expect(toolCalls.calls[0].arguments.stableJsonString == expectedArguments.stableJsonString)

    guard let toolOutput = firstToolOutput(in: generatedTranscript) else {
      Issue.record("Expected tool output entry")
      return
    }
    guard case let .structure(structuredSegment) = toolOutput.segment else {
      Issue.record("Expected tool output to be structured")
      return
    }

    #expect(structuredSegment.content.generatedContent.kind == .string("Sunny"))

    guard let response = lastStructuredResponse(in: generatedTranscript) else {
      Issue.record("Expected structured response entry")
      return
    }

    #expect(response.typeName == WeatherReport.name)
  }

  private func validateGeneratedOutputs(_ generatedOutputs: [WeatherReport.Schema.PartiallyGenerated]) {
    #expect(generatedOutputs.isEmpty == false)

    let last = generatedOutputs.last
    #expect(last?.temperature == 21)
    #expect(last?.condition == "Sunny")
  }

  private func firstToolCalls(
    in transcript: Transcript,
  ) -> Transcript.ToolCalls? {
    for entry in transcript {
      guard case let .toolCalls(toolCalls) = entry else {
        continue
      }

      return toolCalls
    }

    return nil
  }

  private func firstToolOutput(
    in transcript: Transcript,
  ) -> Transcript.ToolOutput? {
    for entry in transcript {
      guard case let .toolOutput(toolOutput) = entry else {
        continue
      }

      return toolOutput
    }

    return nil
  }

  private func lastStructuredResponse(
    in transcript: Transcript,
  ) -> Transcript.StructuredSegment? {
    var segment: Transcript.StructuredSegment?

    for entry in transcript {
      guard case let .response(response) = entry else {
        continue
      }

      segment = response.structuredSegments.last
    }

    return segment
  }
}

// MARK: - Tool

private struct WeatherTool: FoundationModels.Tool {
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

// MARK: - Structured Output

private struct WeatherReport: StructuredOutput {
  static let name: String = "weather_report"

  @Generable
  struct Schema {
    var temperature: Int
    var condition: String
  }
}

// MARK: - Mock Responses

private let streamingToolCallResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01WeatherToolCallStream","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":64,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":12,"service_tier":"standard"}} }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01WeatherToolCallStream","name":"get_weather","input":{}} }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"loc"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ation\":\"Tokyo\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0 }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":64,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":12} }

event: message_stop
data: {"type":"message_stop" }
"""#

private let streamingStructuredOutputResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01WeatherStructuredStream","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":84,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":17,"service_tier":"standard"}} }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01WeatherStructuredStream","name":"swiftagent_structured_output","input":{}} }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"tem"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"perature\":21,\"cond"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ition\":\"Sunny\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0 }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":84,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":17} }

event: message_stop
data: {"type":"message_stop" }
"""#
