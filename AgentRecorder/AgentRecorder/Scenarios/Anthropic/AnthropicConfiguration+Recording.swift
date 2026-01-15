// By Dennis Müller

import AnthropicSession
import Foundation
import SwiftAgent

extension AnthropicConfiguration {
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
