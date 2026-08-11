import AppKit
import Foundation

public protocol ImageNaming: Sendable {
  func suggestName(for imageURL: URL) async throws -> String
}

public enum ImageAutonamerError: LocalizedError, Sendable {
  case cannotDecodeImage(URL)
  case changedDuringAnalysis
  case invalidHTTPResponse
  case ollamaError(String)
  case unexpectedResponse
  case unusableFilename

  public var errorDescription: String? {
    switch self {
    case .cannotDecodeImage(let url):
      "Could not decode \(url.lastPathComponent)."
    case .changedDuringAnalysis:
      "The file changed while it was being analyzed."
    case .invalidHTTPResponse:
      "Ollama returned an invalid HTTP response."
    case .ollamaError(let message):
      message
    case .unexpectedResponse:
      "Ollama returned an unexpected response."
    case .unusableFilename:
      "The model did not return a usable filename."
    }
  }
}

public struct OllamaClient: ImageNaming {
  public let model: String
  public let endpoint: URL

  public init(
    model: String = "qwen3-vl:4b",
    endpoint: URL = URL(string: "http://127.0.0.1:11434")!
  ) {
    self.model = model
    self.endpoint = endpoint
  }

  public func suggestName(for imageURL: URL) async throws -> String {
    let imageData = try Self.portableImageData(from: imageURL)
    let schema: [String: Any] = [
      "type": "object",
      "properties": ["filename": ["type": "string"]],
      "required": ["filename"],
      "additionalProperties": false,
    ]
    let payload: [String: Any] = [
      "model": model,
      "prompt": Self.prompt,
      "images": [imageData.base64EncodedString()],
      "stream": false,
      "think": false,
      "format": schema,
      "options": ["temperature": 0.2],
    ]
    var request = URLRequest(url: endpoint.appending(path: "api/generate"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ImageAutonamerError.invalidHTTPResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
      throw ImageAutonamerError.ollamaError("Ollama error: \(body)")
    }
    let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
    for candidate in [result.response, result.thinking].compactMap({ $0 }).filter({ !$0.isEmpty }) {
      guard let candidateData = candidate.data(using: .utf8),
        let name = try? JSONDecoder().decode(NameResponse.self, from: candidateData).filename
      else {
        continue
      }
      return name
    }
    throw ImageAutonamerError.unexpectedResponse
  }

  private static func portableImageData(from url: URL) throws -> Data {
    guard let image = NSImage(contentsOf: url),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else {
      throw ImageAutonamerError.cannotDecodeImage(url)
    }
    return png
  }

  private struct OllamaResponse: Decodable {
    let response: String?
    let thinking: String?
  }

  private struct NameResponse: Decodable {
    let filename: String
  }

  private static let prompt = """
    Create a concise, descriptive filename for this image.
    Describe only what is visibly important and avoid guessing names, locations, or sensitive traits.
    Return JSON with exactly one field named "filename".
    The filename must contain 3 to 8 lowercase words separated by hyphens, with no extension.
    Prefer concrete subjects, actions, setting, and distinctive visible text when useful.
    Do not include filler words, punctuation, a path, or commentary.
    """
}
