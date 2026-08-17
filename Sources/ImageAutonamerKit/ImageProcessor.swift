import Foundation

public struct ProcessingEvent: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case baseline
    case queued
    case renamed
    case rejected
    case undone
    case skipped
    case failed
  }

  public enum Recovery: Sendable, Equatable {
    case installOllama
    case pullModel(String)
    case reauthorizeFolder
  }

  public let kind: Kind
  public let message: String
  public let recovery: Recovery?

  public init(kind: Kind, message: String, recovery: Recovery? = nil) {
    self.kind = kind
    self.message = message
    self.recovery = recovery
  }
}

public struct ReviewItem: Codable, Identifiable, Sendable, Equatable {
  public let id: UUID
  public let sourcePath: String
  public let proposedStem: String
  public let evidence: [String]
  public let createdAt: Date
  let sourceFingerprint: FileFingerprint

  public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
  public var originalFilename: String { sourceURL.lastPathComponent }
  public var proposedFilename: String {
    "\(proposedStem).\(sourceURL.pathExtension.lowercased())"
  }
}

public struct RenameRecord: Codable, Identifiable, Sendable, Equatable {
  public let id: UUID
  public let originalPath: String
  public let renamedPath: String
  public let renamedAt: Date
  public var undoneAt: Date?

  public var originalFilename: String { URL(fileURLWithPath: originalPath).lastPathComponent }
  public var renamedFilename: String { URL(fileURLWithPath: renamedPath).lastPathComponent }
  public var canUndo: Bool { undoneAt == nil }
}

public struct ReviewSnapshot: Sendable, Equatable {
  public let pending: [ReviewItem]
  public let history: [RenameRecord]
}

public actor ImageProcessor {
  fileprivate static let supportedTypesVersion = 2
  private static let supportedExtensions = Set([
    "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "pdf", "png", "tif", "tiff",
    "webp",
  ])

  private let directory: URL
  private let stateURL: URL
  private let namer: any ImageNaming
  private let settleSeconds: TimeInterval
  private let reviewBeforeRenaming: Bool
  private var state: ProcessingState
  private var isScanning = false

  public init(
    directory: URL,
    stateURL: URL,
    namer: any ImageNaming,
    reviewBeforeRenaming: Bool = false,
    settleSeconds: TimeInterval = 15
  ) {
    self.directory = directory
    self.stateURL = stateURL
    self.namer = namer
    self.reviewBeforeRenaming = reviewBeforeRenaming
    self.settleSeconds = settleSeconds
    state = Self.loadState(from: stateURL)
  }

  public func reviewSnapshot() -> ReviewSnapshot {
    ReviewSnapshot(
      pending: state.pending.sorted { $0.createdAt < $1.createdAt },
      history: state.history.sorted { $0.renamedAt > $1.renamedAt }
    )
  }

  public func approveReview(id: UUID, editedStem: String? = nil) throws -> ProcessingEvent {
    guard let index = state.pending.firstIndex(where: { $0.id == id }) else {
      throw ImageAutonamerError.reviewItemUnavailable
    }
    let item = state.pending[index]
    guard FileManager.default.fileExists(atPath: item.sourcePath) else {
      state.pending.remove(at: index)
      state.files.removeValue(forKey: item.sourcePath)
      try saveState()
      throw ImageAutonamerError.reviewSourceMissing
    }
    guard try fingerprint(for: item.sourceURL) == item.sourceFingerprint else {
      state.pending.remove(at: index)
      state.files.removeValue(forKey: item.sourcePath)
      try saveState()
      throw ImageAutonamerError.changedDuringAnalysis
    }
    let stem = try FilenameSanitizer.slugify(editedStem ?? item.proposedStem)
    let event = try rename(
      source: item.sourceURL,
      stem: stem,
      originalFingerprint: item.sourceFingerprint
    )
    state.pending.remove(at: index)
    try saveState()
    return event
  }

  public func approveAllReviews(editedStems: [UUID: String] = [:]) -> [ProcessingEvent] {
    let ids = state.pending.map(\.id)
    return ids.map { id in
      do {
        return try approveReview(id: id, editedStem: editedStems[id])
      } catch {
        return Self.failureEvent(for: error)
      }
    }
  }

  public func rejectReview(id: UUID) throws -> ProcessingEvent {
    guard let index = state.pending.firstIndex(where: { $0.id == id }) else {
      throw ImageAutonamerError.reviewItemUnavailable
    }
    let item = state.pending.remove(at: index)
    try saveState()
    return ProcessingEvent(kind: .rejected, message: "Kept \(item.originalFilename) unchanged.")
  }

  public func undoRename(id: UUID) throws -> ProcessingEvent {
    guard let index = state.history.firstIndex(where: { $0.id == id }),
      state.history[index].undoneAt == nil
    else {
      throw ImageAutonamerError.reviewItemUnavailable
    }
    let record = state.history[index]
    let renamedURL = URL(fileURLWithPath: record.renamedPath)
    let originalURL = URL(fileURLWithPath: record.originalPath)
    guard FileManager.default.fileExists(atPath: renamedURL.path) else {
      throw ImageAutonamerError.reviewSourceMissing
    }
    guard !FileManager.default.fileExists(atPath: originalURL.path) else {
      throw ImageAutonamerError.undoDestinationExists(originalURL.lastPathComponent)
    }
    try FileManager.default.linkItem(at: renamedURL, to: originalURL)
    do {
      try FileManager.default.removeItem(at: renamedURL)
    } catch {
      try? FileManager.default.removeItem(at: originalURL)
      throw error
    }
    state.files.removeValue(forKey: renamedURL.path)
    state.files[originalURL.path] = try fingerprint(for: originalURL)
    state.history[index].undoneAt = Date()
    try saveState()
    return ProcessingEvent(
      kind: .undone,
      message: "Restored \(originalURL.lastPathComponent)."
    )
  }

  public func scan(force: Bool = false) async -> [ProcessingEvent] {
    guard !isScanning else { return [] }
    isScanning = true
    defer { isScanning = false }

    do {
      let files = try discoverSupportedFiles()
      if !state.didBaseline, !force {
        for file in files {
          state.files[file.path] = try fingerprint(for: file)
        }
        state.didBaseline = true
        state.supportedTypesVersion = Self.supportedTypesVersion
        try saveState()
        return [
          ProcessingEvent(kind: .baseline, message: "Protected \(files.count) existing file(s).")
        ]
      }

      if state.supportedTypesVersion < Self.supportedTypesVersion, !force {
        let existingPDFs = files.filter { $0.pathExtension.lowercased() == "pdf" }
        for pdf in existingPDFs {
          state.files[pdf.path] = try fingerprint(for: pdf)
        }
        state.supportedTypesVersion = Self.supportedTypesVersion
        try saveState()
        return [
          ProcessingEvent(
            kind: .baseline,
            message: "Protected \(existingPDFs.count) existing PDF(s) during upgrade."
          )
        ]
      }

      var events: [ProcessingEvent] = []
      for file in files {
        do {
          if let event = try await process(file, force: force) {
            events.append(event)
          }
        } catch {
          events.append(Self.failureEvent(for: error, filename: file.lastPathComponent))
        }
      }
      if force,
        !state.didBaseline || state.supportedTypesVersion < Self.supportedTypesVersion
      {
        state.didBaseline = true
        state.supportedTypesVersion = Self.supportedTypesVersion
        try saveState()
      }
      return events
    } catch {
      return [Self.failureEvent(for: error)]
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

    let suggestion = try await namer.suggest(for: source)
    let stem = try FilenameSanitizer.slugify(suggestion.name)
    guard try fingerprint(for: source) == originalFingerprint else {
      throw ImageAutonamerError.changedDuringAnalysis
    }

    if suggestion.disposition == .keep {
      state.files[source.path] = originalFingerprint
      try saveState()
      return ProcessingEvent(
        kind: .skipped,
        message: "Kept \(source.lastPathComponent). \(decisionSummary(from: suggestion.evidence))"
      )
    }

    if reviewBeforeRenaming || suggestion.disposition == .review {
      let item = ReviewItem(
        id: UUID(),
        sourcePath: source.path,
        proposedStem: stem,
        evidence: suggestion.evidence,
        createdAt: Date(),
        sourceFingerprint: originalFingerprint
      )
      state.pending.removeAll { $0.sourcePath == source.path }
      state.pending.append(item)
      state.files[source.path] = originalFingerprint
      try saveState()
      return ProcessingEvent(kind: .queued, message: "Review \(item.proposedFilename).")
    }

    return try rename(source: source, stem: stem, originalFingerprint: originalFingerprint)
  }

  private func decisionSummary(from evidence: [String]) -> String {
    evidence.first(where: { $0.hasPrefix("Decision: ") })?
      .replacingOccurrences(of: "Decision: ", with: "")
      ?? "The existing filename is already useful."
  }

  private func rename(
    source: URL,
    stem: String,
    originalFingerprint: FileFingerprint
  ) throws -> ProcessingEvent {
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
      } catch where FileManager.default.fileExists(atPath: destination.path) {
        destination = uniqueDestination(for: source, stem: stem)
      }
    }
    do {
      try FileManager.default.removeItem(at: source)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    state.files.removeValue(forKey: source.path)
    state.files[destination.path] = try fingerprint(for: destination)
    state.history.insert(
      RenameRecord(
        id: UUID(),
        originalPath: source.path,
        renamedPath: destination.path,
        renamedAt: Date(),
        undoneAt: nil
      ),
      at: 0
    )
    state.history = Array(state.history.prefix(100))
    try saveState()
    return ProcessingEvent(
      kind: .renamed,
      message: "\(source.lastPathComponent) → \(destination.lastPathComponent)"
    )
  }

  private func discoverSupportedFiles() throws -> [URL] {
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

  private static func failureEvent(for error: Error, filename: String? = nil) -> ProcessingEvent {
    let recovery: ProcessingEvent.Recovery?
    switch error {
    case ImageAutonamerError.ollamaUnavailable:
      recovery = .installOllama
    case ImageAutonamerError.modelUnavailable(let model):
      recovery = .pullModel(model)
    case let cocoaError as CocoaError
    where cocoaError.code == .fileReadNoPermission || cocoaError.code == .fileWriteNoPermission:
      recovery = .reauthorizeFolder
    default:
      recovery = nil
    }
    let prefix = filename.map { "\($0): " } ?? ""
    return ProcessingEvent(
      kind: .failed,
      message: "\(prefix)\(error.localizedDescription)",
      recovery: recovery
    )
  }
}

struct FileFingerprint: Codable, Equatable, Sendable {
  let size: Int64
  let modifiedAt: Date
}

private struct ProcessingState: Codable, Sendable {
  var didBaseline = false
  var supportedTypesVersion = ImageProcessor.supportedTypesVersion
  var files: [String: FileFingerprint] = [:]
  var pending: [ReviewItem] = []
  var history: [RenameRecord] = []

  init() {}

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    didBaseline = try container.decodeIfPresent(Bool.self, forKey: .didBaseline) ?? false
    supportedTypesVersion =
      try container.decodeIfPresent(Int.self, forKey: .supportedTypesVersion) ?? 1
    files = try container.decodeIfPresent([String: FileFingerprint].self, forKey: .files) ?? [:]
    pending = try container.decodeIfPresent([ReviewItem].self, forKey: .pending) ?? []
    history = try container.decodeIfPresent([RenameRecord].self, forKey: .history) ?? []
  }
}
