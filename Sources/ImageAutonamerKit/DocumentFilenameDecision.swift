import Foundation
import PDFKit
import Vision

struct DocumentTextEvidence: Sendable, Equatable {
  enum Source: String, Sendable {
    case embedded = "embedded PDF text"
    case visionOCR = "local Vision OCR"
  }

  let text: String
  let source: Source
}

enum DocumentTextExtractor {
  static func extract(from url: URL, renderedPages: [Data]) -> DocumentTextEvidence? {
    guard let document = PDFDocument(url: url), !document.isLocked else { return nil }
    let embedded = normalized(
      (0..<min(document.pageCount, 3))
        .compactMap { document.page(at: $0)?.string }
        .joined(separator: "\n")
    )
    if embedded.count >= 80 {
      return DocumentTextEvidence(text: bounded(embedded), source: .embedded)
    }

    let recognized = normalized(
      renderedPages.compactMap { try? recognizeText(in: $0) }.joined(separator: "\n")
    )
    guard recognized.count >= 30 else { return nil }
    return DocumentTextEvidence(text: bounded(recognized), source: .visionOCR)
  }

  private static func recognizeText(in data: Data) throws -> String? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(data: data)
    try handler.perform([request])
    return request.results?
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }

  private static func normalized(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func bounded(_ value: String) -> String {
    String(value.prefix(12_000))
  }
}

struct DocumentFilenameDecision: Sendable, Equatable {
  let disposition: NamingDisposition
  let reason: String
}

enum DocumentFilenameDecisionEngine {
  private static let genericWords = Set([
    "copy", "doc", "document", "download", "file", "final", "new", "pdf", "scan",
    "scanned", "untitled",
  ])

  static func evaluate(
    originalFilename: String,
    proposedName: String,
    extractedText: String?
  ) -> DocumentFilenameDecision {
    let originalStem = URL(fileURLWithPath: originalFilename)
      .deletingPathExtension().lastPathComponent
    let original = tokens(originalStem)
    let proposed = tokens(proposedName)

    guard let extractedText, extractedText.count >= 30 else {
      return DocumentFilenameDecision(
        disposition: .keep,
        reason: "Not enough document text could be extracted safely."
      )
    }
    if original == proposed {
      return DocumentFilenameDecision(
        disposition: .keep,
        reason: "The existing filename already matches the proposed name."
      )
    }

    let evidence = Set(tokens(extractedText))
    let originalSignal = signalTokens(original).filter(evidence.contains)
    let proposedSignal = signalTokens(proposed).filter(evidence.contains)
    let originalSet = Set(originalSignal)
    let proposedSet = Set(proposedSignal)
    let lost = originalSet.subtracting(proposedSet)
    let added = proposedSet.subtracting(originalSet)

    if isGeneric(original), proposedSignal.count >= 2 {
      return DocumentFilenameDecision(
        disposition: .rename,
        reason: "The existing filename is generic and the proposal adds visible document details."
      )
    }
    if lost.contains(where: isHighValue) {
      return DocumentFilenameDecision(
        disposition: .keep,
        reason: "The proposal would discard a visible date or reference from the existing filename."
      )
    }
    if originalSignal.count >= 3, !lost.isEmpty, added.count <= lost.count {
      return DocumentFilenameDecision(
        disposition: .keep,
        reason: "The existing filename preserves at least as much visible document information."
      )
    }
    if !originalSignal.isEmpty, lost.isEmpty, added.count >= 2 {
      return DocumentFilenameDecision(
        disposition: .rename,
        reason: "The proposal preserves the existing signal and adds visible details."
      )
    }
    return DocumentFilenameDecision(
      disposition: .review,
      reason: "The proposal changes useful filename information without a clear net improvement."
    )
  }

  private static func isGeneric(_ words: [String]) -> Bool {
    guard !words.isEmpty else { return true }
    if words.allSatisfy({ Int($0) != nil }) { return true }
    if words.count == 1, genericWords.contains(words[0]) || words[0].count < 4 { return true }
    if words.allSatisfy({ genericWords.contains($0) || Int($0) != nil }) { return true }
    let joined = words.joined()
    return joined.range(
      of: #"^[0-9a-f]{24,}$"#,
      options: .regularExpression
    ) != nil
  }

  private static func signalTokens(_ words: [String]) -> [String] {
    words.filter { word in
      !genericWords.contains(word) && (word.count >= 3 || Int(word) != nil)
    }
  }

  private static func isHighValue(_ word: String) -> Bool {
    guard word.allSatisfy(\.isNumber) else { return false }
    return word.count >= 4
  }

  private static func tokens(_ value: String) -> [String] {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }
  }
}
