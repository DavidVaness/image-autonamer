import Foundation
import ImageIO

public enum NamingStyle: String, CaseIterable, Codable, Sendable {
  case descriptive
  case dateDescriptive
  case documents

  public var title: String {
    switch self {
    case .descriptive: "Descriptive"
    case .dateDescriptive: "Date + descriptive"
    case .documents: "Documents"
    }
  }

  public var explanation: String {
    switch self {
    case .descriptive:
      "A concise description of the visible subject."
    case .dateDescriptive:
      "Prefixes the capture date, or the file date when capture metadata is unavailable."
    case .documents:
      "Detects the document type and builds a type-specific name from visible metadata."
    }
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    if value == "businessDocument" {
      self = .documents
    } else if let style = Self(rawValue: value) {
      self = style
    } else {
      throw DecodingError.dataCorruptedError(
        in: try decoder.singleValueContainer(),
        debugDescription: "Unknown naming style: \(value)"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public enum DocumentKind: String, CaseIterable, Codable, Sendable {
  case invoice
  case receipt
  case statement
  case contract
  case letter
  case report
  case certificate
  case taxDocument = "tax_document"
  case other

  public var title: String {
    switch self {
    case .invoice: "Invoice"
    case .receipt: "Receipt"
    case .statement: "Statement"
    case .contract: "Contract"
    case .letter: "Letter"
    case .report: "Report"
    case .certificate: "Certificate"
    case .taxDocument: "Tax document"
    case .other: "Other document"
    }
  }

  static func inferred(from value: String) -> Self {
    let normalized = value.lowercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_")
    return Self(rawValue: normalized) ?? .other
  }

  fileprivate var filenameWords: [String] {
    switch self {
    case .taxDocument: ["tax", "document"]
    case .other: ["document"]
    default: [rawValue]
    }
  }
}

public struct NamingConfiguration: Codable, Equatable, Sendable {
  public var style: NamingStyle
  public var analysisContext: String

  public init(
    style: NamingStyle = .descriptive,
    analysisContext: String = ""
  ) {
    self.style = style
    self.analysisContext = Self.cleanContext(analysisContext)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    style = try container.decodeIfPresent(NamingStyle.self, forKey: .style) ?? .descriptive
    analysisContext = Self.cleanContext(
      try container.decodeIfPresent(String.self, forKey: .analysisContext) ?? ""
    )
  }

  private enum CodingKeys: String, CodingKey {
    case style
    case analysisContext
  }

  public static func cleanContext(_ value: String) -> String {
    let normalized = value.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return String(normalized.prefix(500))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct ImageNamingAnalysis: Decodable, Equatable, Sendable {
  let description: String
  let organization: String
  let organizationVisible: Bool
  let documentType: String
  let documentDate: String
  let documentDateVisible: Bool
  let documentReference: String
  let documentReferenceVisible: Bool
  let documentPeriod: String
  let documentPeriodVisible: Bool

  init(
    description: String,
    organization: String,
    organizationVisible: Bool,
    documentType: String,
    documentDate: String = "",
    documentDateVisible: Bool = false,
    documentReference: String = "",
    documentReferenceVisible: Bool = false,
    documentPeriod: String = "",
    documentPeriodVisible: Bool = false
  ) {
    self.description = description
    self.organization = organization
    self.organizationVisible = organizationVisible
    self.documentType = documentType
    self.documentDate = documentDate
    self.documentDateVisible = documentDateVisible
    self.documentReference = documentReference
    self.documentReferenceVisible = documentReferenceVisible
    self.documentPeriod = documentPeriod
    self.documentPeriodVisible = documentPeriodVisible
  }

  enum CodingKeys: String, CodingKey {
    case description
    case organization
    case organizationVisible = "organization_visible"
    case documentType = "document_type"
    case documentDate = "document_date"
    case documentDateVisible = "document_date_visible"
    case documentReference = "document_reference"
    case documentReferenceVisible = "document_reference_visible"
    case documentPeriod = "document_period"
    case documentPeriodVisible = "document_period_visible"
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
    case .documents:
      return composeDocument(analysis)
    }
  }

  private static func composeDocument(_ analysis: ImageNamingAnalysis) -> String {
    let kind = DocumentKind.inferred(from: analysis.documentType)
    let date = analysis.documentDateVisible ? validDate(analysis.documentDate) : nil
    let period = analysis.documentPeriodVisible ? validPeriod(analysis.documentPeriod) : nil
    let reference =
      analysis.documentReferenceVisible ? tokens(analysis.documentReference) : []
    let organization = analysis.organizationVisible ? tokens(analysis.organization) : []
    var words: [String] = []

    switch kind {
    case .statement, .taxDocument:
      merge(tokens(period ?? date ?? ""), into: &words)
    default:
      merge(tokens(date ?? ""), into: &words)
    }
    merge(organization, into: &words)
    merge(kind.filenameWords, into: &words)

    switch kind {
    case .invoice, .statement, .certificate, .taxDocument:
      merge(reference, into: &words)
    case .receipt, .contract, .letter, .report, .other:
      break
    }

    merge(tokens(analysis.description), into: &words)
    return words.joined(separator: " ")
  }

  private static func validDate(_ value: String) -> String? {
    guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: value).map { _ in value }
  }

  private static func validPeriod(_ value: String) -> String? {
    if value.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
      return value
    }
    let components = value.components(separatedBy: "-to-")
    guard components.count <= 2, components.allSatisfy(validYearMonth) else {
      return nil
    }
    return value
  }

  private static func validYearMonth(_ value: String) -> Bool {
    guard value.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil,
      let month = Int(value.suffix(2))
    else {
      return false
    }
    return (1...12).contains(month)
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
