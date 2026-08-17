import Foundation

public enum FilenameSanitizer {
  private static let supportedExtensions = Set([
    "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "pdf", "png", "tif", "tiff",
    "webp",
  ])

  public static func slugify(
    _ value: String,
    maxWords: Int = 16,
    maxLength: Int = 96
  ) throws -> String {
    let folded =
      value
      .folding(
        options: [.diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased()
    let expression = try NSRegularExpression(pattern: "[a-z0-9]+")
    let range = NSRange(folded.startIndex..., in: folded)
    var words = expression.matches(in: folded, range: range).compactMap { match -> String? in
      guard let range = Range(match.range, in: folded) else { return nil }
      return String(folded[range])
    }
    words = Array(words.prefix(maxWords))
    if let last = words.last, supportedExtensions.contains(last) {
      words.removeLast()
    }
    let slug = String(words.joined(separator: "-").prefix(maxLength))
      .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    guard !slug.isEmpty, slug != ".", slug != ".." else {
      throw ImageAutonamerError.unusableFilename
    }
    return slug
  }
}
