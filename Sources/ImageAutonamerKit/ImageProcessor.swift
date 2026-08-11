import Foundation

public struct ProcessingEvent: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case baseline
    case renamed
    case skipped
    case failed
  }

  public let kind: Kind
  public let message: String

  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }
}

public actor ImageProcessor {
  private static let supportedExtensions = Set([
    "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp",
  ])

  private let directory: URL
  private let stateURL: URL
  private let namer: any ImageNaming
  private let settleSeconds: TimeInterval
  private var state: ProcessingState
  private var isScanning = false

  public init(
    directory: URL,
    stateURL: URL,
    namer: any ImageNaming,
    settleSeconds: TimeInterval = 15
  ) {
    self.directory = directory
    self.stateURL = stateURL
    self.namer = namer
    self.settleSeconds = settleSeconds
    state = Self.loadState(from: stateURL)
  }

  public func scan(force: Bool = false) async -> [ProcessingEvent] {
    guard !isScanning else { return [] }
    isScanning = true
    defer { isScanning = false }

    do {
      let images = try discoverImages()
      if !state.didBaseline, !force {
        for image in images {
          state.files[image.path] = try fingerprint(for: image)
        }
        state.didBaseline = true
        try saveState()
        return [
          ProcessingEvent(kind: .baseline, message: "Protected \(images.count) existing image(s).")
        ]
      }

      var events: [ProcessingEvent] = []
      for image in images {
        do {
          if let event = try await process(image, force: force) {
            events.append(event)
          }
        } catch {
          events.append(
            ProcessingEvent(
              kind: .failed,
              message: "\(image.lastPathComponent): \(error.localizedDescription)"
            )
          )
        }
      }
      if force, !state.didBaseline {
        state.didBaseline = true
        try saveState()
      }
      return events
    } catch {
      return [ProcessingEvent(kind: .failed, message: error.localizedDescription)]
    }
  }

  private func process(_ source: URL, force: Bool) async throws -> ProcessingEvent? {
    let originalFingerprint = try fingerprint(for: source)
    if !force, state.files[source.path] == originalFingerprint {
      return nil
    }
    if Date().timeIntervalSince(originalFingerprint.modifiedAt) < settleSeconds {
      return nil
    }

    let suggestion = try await namer.suggestName(for: source)
    let stem = try FilenameSanitizer.slugify(suggestion)
    guard try fingerprint(for: source) == originalFingerprint else {
      throw ImageAutonamerError.changedDuringAnalysis
    }

    var destination = uniqueDestination(for: source, stem: stem)
    if destination.standardizedFileURL == source.standardizedFileURL {
      state.files[source.path] = originalFingerprint
      try saveState()
      return ProcessingEvent(
        kind: .skipped, message: "\(source.lastPathComponent) already has the suggested name.")
    }

    while true {
      do {
        try FileManager.default.linkItem(at: source, to: destination)
        break
      } catch  where FileManager.default.fileExists(atPath: destination.path) {
        destination = uniqueDestination(for: source, stem: stem)
      }
    }
    try FileManager.default.removeItem(at: source)
    state.files[destination.path] = try fingerprint(for: destination)
    try saveState()
    return ProcessingEvent(
      kind: .renamed,
      message: "\(source.lastPathComponent) → \(destination.lastPathComponent)"
    )
  }

  private func discoverImages() throws -> [URL] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    return try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles]
    )
    .filter { url in
      guard Self.supportedExtensions.contains(url.pathExtension.lowercased()),
        let values = try? url.resourceValues(forKeys: keys)
      else {
        return false
      }
      return values.isRegularFile == true && values.isSymbolicLink != true
    }
    .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
  }

  private func uniqueDestination(for source: URL, stem: String) -> URL {
    let fileExtension = source.pathExtension.lowercased()
    var counter = 1
    while true {
      let suffix = counter == 1 ? "" : "-\(counter)"
      let candidate = source.deletingLastPathComponent()
        .appending(path: "\(stem)\(suffix).\(fileExtension)")
      if candidate.standardizedFileURL == source.standardizedFileURL
        || !FileManager.default.fileExists(atPath: candidate.path)
      {
        return candidate
      }
      counter += 1
    }
  }

  private func fingerprint(for url: URL) throws -> FileFingerprint {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    guard let size = values.fileSize, let modifiedAt = values.contentModificationDate else {
      throw CocoaError(.fileReadUnknown)
    }
    return FileFingerprint(size: Int64(size), modifiedAt: modifiedAt)
  }

  private static func loadState(from url: URL) -> ProcessingState {
    guard let data = try? Data(contentsOf: url),
      let state = try? JSONDecoder().decode(ProcessingState.self, from: data)
    else {
      return ProcessingState()
    }
    return state
  }

  private func saveState() throws {
    try FileManager.default.createDirectory(
      at: stateURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(state)
    try data.write(to: stateURL, options: .atomic)
  }
}

private struct FileFingerprint: Codable, Equatable, Sendable {
  let size: Int64
  let modifiedAt: Date
}

private struct ProcessingState: Codable, Sendable {
  var didBaseline = false
  var files: [String: FileFingerprint] = [:]
}
