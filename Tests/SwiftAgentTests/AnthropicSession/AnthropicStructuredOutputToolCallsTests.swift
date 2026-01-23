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

@Suite("Anthropic - Structured Output - Tool Calls")
struct AnthropicStructuredOutputToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<MessageParameter>

  init() async {
    mockHTTPClient = ReplayHTTPClient<MessageParameter>(
      recordedResponses: [
        .init(body: toolCallResponse),
        .init(body: structuredOutputResponse),
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

  @Test("Runs tool calls before emitting structured output")
  func runsToolsBeforeStructuredOutput() async throws {
    let agentResponse = try await session.respond(
      to: "Weather update",
      generating: WeatherReport.self,
      using: .other("claude-haiku-4-5"),
    )

    try await validateHTTPRequests()
    try validateAgentResponse(agentResponse)
  }

  private func validateHTTPRequests() async throws {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 2)

    let request = recordedRequests[0]
    let json = try requestJSON(from: request.body)

    guard let toolChoice = json["tool_choice"] as? [String: Any] else {
      Issue.record("Expected tool_choice in request JSON")
      return
    }

    #expect(toolChoice["type"] as? String == "any")
    #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)

    guard let tools = json["tools"] as? [[String: Any]] else {
      Issue.record("Expected tools in request JSON")
      return
    }

    let toolNames = tools.compactMap { $0["name"] as? String }
    #expect(toolNames.contains("get_weather"))
    #expect(toolNames.contains("swiftagent_structured_output"))
  }

  private func validateAgentResponse(
    _ agentResponse: AgentResponse<WeatherReport>,
  ) throws {
    #expect(agentResponse.content.temperature == 21)
    #expect(agentResponse.content.condition == "Sunny")

    let generatedTranscript = agentResponse.transcript

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

  private func requestJSON(
    from request: MessageParameter,
  ) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(request)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let json = object as? [String: Any] else {
      throw GenerationError.requestFailed(
        reason: .decodingFailure,
        detail: "Failed to decode request JSON",
      )
    }

    return json
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

private let toolCallResponse: String = #"""
{
  "content" : [
    {
      "id" : "toolu_01WeatherToolCall",
      "input" : {
        "location" : "Tokyo"
      },
      "name" : "get_weather",
      "type" : "tool_use"
    }
  ],
  "id" : "msg_01WeatherToolCall",
  "model" : "claude-haiku-4-5-20251001",
  "role" : "assistant",
  "stop_reason" : "tool_use",
  "stop_sequence" : null,
  "type" : "message",
  "usage" : {
    "cache_creation" : {
      "ephemeral_1h_input_tokens" : 0,
      "ephemeral_5m_input_tokens" : 0
    },
    "cache_creation_input_tokens" : 0,
    "cache_read_input_tokens" : 0,
    "input_tokens" : 64,
    "output_tokens" : 12,
    "service_tier" : "standard"
  }
}
"""#

private let structuredOutputResponse: String = #"""
{
  "content" : [
    {
      "id" : "toolu_01WeatherStructured",
      "input" : {
        "condition" : "Sunny",
        "temperature" : 21
      },
      "name" : "swiftagent_structured_output",
      "type" : "tool_use"
    }
  ],
  "id" : "msg_01WeatherStructured",
  "model" : "claude-haiku-4-5-20251001",
  "role" : "assistant",
  "stop_reason" : "tool_use",
  "stop_sequence" : null,
  "type" : "message",
  "usage" : {
    "cache_creation" : {
      "ephemeral_1h_input_tokens" : 0,
      "ephemeral_5m_input_tokens" : 0
    },
    "cache_creation_input_tokens" : 0,
    "cache_read_input_tokens" : 0,
    "input_tokens" : 84,
    "output_tokens" : 17,
    "service_tier" : "standard"
  }
}
"""#
