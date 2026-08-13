import Foundation
import ImageIO

public enum NamingStyle: String, CaseIterable, Codable, Sendable {
  case descriptive
  case dateDescriptive
  case businessDocument

  public var title: String {
    switch self {
    case .descriptive: "Descriptive"
    case .dateDescriptive: "Date + descriptive"
    case .businessDocument: "Business document"
    }
  }

  public var explanation: String {
    switch self {
    case .descriptive:
      "A concise description of the visible subject."
    case .dateDescriptive:
      "Prefixes the capture date, or the file date when capture metadata is unavailable."
    case .businessDocument:
      "Prioritizes visible organizations, document types, and business context."
    }
  }
}

public struct NamingConfiguration: Codable, Equatable, Sendable {
  public var style: NamingStyle
  public var knownOrganizations: [String]

  public init(
    style: NamingStyle = .descriptive,
    knownOrganizations: [String] = []
  ) {
    self.style = style
    self.knownOrganizations = Self.cleanOrganizations(knownOrganizations)
  }

  public static func cleanOrganizations(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      let cleaned =
        value
        .components(separatedBy: .newlines)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleaned.isEmpty else { return nil }
      let limited = String(cleaned.prefix(60))
      let key = limited.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      guard seen.insert(key).inserted else { return nil }
      return limited
    }
    .prefix(20)
    .map { $0 }
  }
}

struct ImageNamingAnalysis: Decodable, Equatable, Sendable {
  let description: String
  let organization: String
  let organizationVisible: Bool
  let documentType: String

  enum CodingKeys: String, CodingKey {
    case description
    case organization
    case organizationVisible = "organization_visible"
    case documentType = "document_type"
  }
}

enum ImageNameComposer {
  static func compose(
    analysis: ImageNamingAnalysis,
    configuration: NamingConfiguration,
    imageDate: Date?
  ) -> String {
    switch configuration.style {
    case .descriptive:
      return analysis.description
    case .dateDescriptive:
      guard let imageDate else { return analysis.description }
      return "\(formatted(imageDate)) \(analysis.description)"
    case .businessDocument:
      var words: [String] = []
      if analysis.organizationVisible, !analysis.organization.isEmpty {
        merge(
          tokens(
            canonicalOrganization(analysis.organization, configuration: configuration)
          ),
          into: &words
        )
      }
      if !analysis.documentType.isEmpty {
        merge(tokens(analysis.documentType), into: &words)
      }
      merge(tokens(analysis.description), into: &words)
      return words.joined(separator: " ")
    }
  }

  private static func canonicalOrganization(
    _ detected: String,
    configuration: NamingConfiguration
  ) -> String {
    configuration.knownOrganizations.first {
      $0.compare(detected, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    } ?? detected
  }

  private static func formatted(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func tokens(_ value: String) -> [String] {
    let folded = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }

  private static func merge(_ incoming: [String], into result: inout [String]) {
    let maximumOverlap = min(result.count, incoming.count)
    let overlap =
      stride(from: maximumOverlap, through: 1, by: -1).first { count in
        Array(result.suffix(count)) == Array(incoming.prefix(count))
      } ?? 0
    result.append(contentsOf: incoming.dropFirst(overlap))
  }
}

enum ImageDateResolver {
  static func date(for url: URL) -> Date? {
    captureDate(for: url) ?? fileDate(for: url)
  }

  private static func captureDate(for url: URL) -> Date? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any]
    else {
      return nil
    }

    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    let candidates = [
      exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
      exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
      tiff?[kCGImagePropertyTIFFDateTime] as? String,
    ]
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return candidates.compactMap { value in value.flatMap(formatter.date(from:)) }.first
  }

  private static func fileDate(for url: URL) -> Date? {
    let values = try? url.resourceValues(forKeys: [
      .creationDateKey, .contentModificationDateKey,
    ])
    return values?.creationDate ?? values?.contentModificationDate
  }
}
