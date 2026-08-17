import AppKit
import Foundation
import ImageAutonamerKit
import OSLog
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppController: ObservableObject {
  private let logger = Logger(
    subsystem: "com.davidvaness.image-autonamer",
    category: "monitor"
  )
  @Published private(set) var activity = "Starting…"
  @Published private(set) var recentEvents: [ProcessingEvent] = []
  @Published private(set) var isScanning = false
  @Published private(set) var launchAtLogin = false
  @Published private(set) var hasFolderAccess = false
  @Published private(set) var recovery: ProcessingEvent.Recovery?
  @Published private(set) var namingStyle: NamingStyle = .descriptive
  @Published private(set) var namingContext = ""
  @Published private(set) var reviewBeforeRenaming = false
  @Published private(set) var pendingReviews: [ReviewItem] = []
  @Published private(set) var renameHistory: [RenameRecord] = []
  @Published private(set) var isApplyingReviews = false
  @Published private(set) var reviewError: String?
  @Published private(set) var isPreviewing = false
  @Published private(set) var previewResult: String?
  @Published private(set) var previewError: String?

  private let defaultDownloadsURL: URL
  private var downloadsURL: URL?
  private var processor: ImageProcessor?
  private var previewTask: Task<Void, Never>?
  private var securityScopedURL: URL?
  private var timer: Timer?
  private static let bookmarkKey = "downloadsSecurityScopedBookmark"
  private static let namingStyleKey = "namingStyle"
  private static let namingContextKey = "namingContext"
  private static let reviewBeforeRenamingKey = "reviewBeforeRenaming"

  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--capture-demo") {
        defaultDownloadsURL = Self.captureDemoDirectory()
        configureCaptureDemo()
        return
      }
    #endif

    defaultDownloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    if let rawStyle = UserDefaults.standard.string(forKey: Self.namingStyleKey) {
      namingStyle =
        rawStyle == "businessDocument"
        ? .documents : NamingStyle(rawValue: rawStyle) ?? .descriptive
    }
    namingContext = UserDefaults.standard.string(forKey: Self.namingContextKey) ?? ""
    reviewBeforeRenaming = UserDefaults.standard.bool(forKey: Self.reviewBeforeRenamingKey)
    let loginService = SMAppService.mainApp
    launchAtLogin = loginService.status == .enabled
    if loginService.status == .notRegistered || loginService.status == .notFound {
      do {
        try loginService.register()
        launchAtLogin = loginService.status == .enabled
      } catch {
        activity = "Enable launch at login from the menu."
      }
    }
    if !restoreFolderAccess() {
      activity = "Choose Downloads to start."
    }
  }

  func scanNow(force: Bool = false) {
    guard !isScanning, let processor else { return }
    isScanning = true
    activity = force ? "Processing existing files…" : "Checking Downloads…"
    Task {
      let events = await processor.scan(force: force)
      if events.isEmpty {
        logger.debug("Scan completed without changes")
      } else {
        for event in events {
          if event.kind == .failed {
            logger.error("\(event.message, privacy: .private)")
          } else {
            logger.info("\(event.message, privacy: .private)")
          }
        }
      }
      recentEvents = Array((events + recentEvents).prefix(8))
      let snapshot = await processor.reviewSnapshot()
      pendingReviews = snapshot.pending
      renameHistory = snapshot.history
      if let failure = events.first(where: { $0.kind == .failed }) {
        if failure.recovery == .reauthorizeFolder {
          invalidateFolderAccess()
        }
        activity = failure.message
        recovery = failure.recovery
      } else if let rename = events.first(where: { $0.kind == .renamed }) {
        activity = rename.message
        recovery = nil
      } else if events.contains(where: { $0.kind == .queued }) {
        activity = "\(snapshot.pending.count) suggestion(s) ready for review."
        recovery = nil
      } else if let baseline = events.first(where: { $0.kind == .baseline }) {
        activity = baseline.message
        recovery = nil
      } else {
        activity = "Watching Downloads"
      }
      isScanning = false
    }
  }

  func setReviewBeforeRenaming(_ enabled: Bool) {
    reviewBeforeRenaming = enabled
    UserDefaults.standard.set(enabled, forKey: Self.reviewBeforeRenamingKey)
    rebuildProcessor()
    activity = enabled ? "New suggestions will wait for review." : "Automatic renaming enabled."
  }

  func refreshReviews() {
    guard let processor else {
      pendingReviews = []
      renameHistory = []
      return
    }
    Task {
      let snapshot = await processor.reviewSnapshot()
      pendingReviews = snapshot.pending
      renameHistory = snapshot.history
    }
  }

  func clearReviewError() {
    reviewError = nil
  }

  func approveReview(id: UUID, editedStem: String) {
    performReviewAction { processor in
      [try await processor.approveReview(id: id, editedStem: editedStem)]
    }
  }

  func approveAllReviews(editedStems: [UUID: String]) {
    performReviewAction { processor in
      await processor.approveAllReviews(editedStems: editedStems)
    }
  }

  func rejectReview(id: UUID) {
    performReviewAction { processor in
      [try await processor.rejectReview(id: id)]
    }
  }

  func undoRename(id: UUID) {
    performReviewAction { processor in
      [try await processor.undoRename(id: id)]
    }
  }

  func revealReviewItem(_ item: ReviewItem) {
    NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
  }

  func revealRenameRecord(_ record: RenameRecord) {
    let path = record.canUndo ? record.renamedPath : record.originalPath
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        if SMAppService.mainApp.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
          activity = "Approve Image Autonamer in Login Items."
          return
        }
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = SMAppService.mainApp.status == .enabled
    } catch {
      activity = "Could not update login item: \(error.localizedDescription)"
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }

  func openDownloads() {
    guard let downloadsURL else { return }
    NSWorkspace.shared.open(downloadsURL)
  }

  func performRecovery() {
    switch recovery {
    case .installOllama:
      NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
    case .pullModel(let model):
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("ollama pull \(model)", forType: .string)
      activity = "Copied ollama pull \(model) to the clipboard."
    case .reauthorizeFolder:
      chooseDownloads()
    case nil:
      break
    }
  }

  func saveNamingSettings(
    style: NamingStyle,
    namingContext: String
  ) {
    let context = NamingConfiguration.cleanContext(namingContext)
    namingStyle = style
    self.namingContext = context
    UserDefaults.standard.set(style.rawValue, forKey: Self.namingStyleKey)
    UserDefaults.standard.set(context, forKey: Self.namingContextKey)
    rebuildProcessor()
    activity = "Using \(style.title.lowercased()) names."
  }

  func previewImage(
    style: NamingStyle,
    namingContext: String
  ) {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    defer {
      NSApplication.shared.setActivationPolicy(.accessory)
    }

    let panel = NSOpenPanel()
    panel.title = "Preview a file name"
    panel.message = "The selected image or PDF is analyzed locally and will not be renamed."
    panel.prompt = "Preview Name"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.image, .pdf]

    guard panel.runModal() == .OK, let imageURL = panel.url else { return }
    let configuration = NamingConfiguration(
      style: style,
      analysisContext: namingContext
    )
    isPreviewing = true
    previewResult = nil
    previewError = nil
    previewTask?.cancel()
    previewTask = Task {
      do {
        let suggestion = try await OllamaClient(configuration: configuration)
          .suggestName(for: imageURL)
        let stem = try FilenameSanitizer.slugify(suggestion)
        guard !Task.isCancelled else { return }
        previewResult =
          "\(imageURL.lastPathComponent) → \(stem).\(imageURL.pathExtension.lowercased())"
      } catch {
        guard !Task.isCancelled else { return }
        previewError = error.localizedDescription
      }
      isPreviewing = false
      previewTask = nil
    }
  }

  func clearPreview() {
    guard !isPreviewing else { return }
    previewResult = nil
    previewError = nil
  }

  func cancelPreview() {
    previewTask?.cancel()
    previewTask = nil
    isPreviewing = false
    previewResult = nil
    previewError = nil
  }

  func chooseDownloads() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    defer {
      NSApplication.shared.setActivationPolicy(.accessory)
    }

    let panel = NSOpenPanel()
    panel.title = "Allow access to Downloads"
    panel.message = "Image Autonamer only needs access to this folder."
    panel.prompt = "Allow Downloads"
    panel.directoryURL = defaultDownloadsURL
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      if !hasFolderAccess {
        activity = "Choose Downloads from the menu to start."
      }
      return
    }
    guard isDownloads(selectedURL) else {
      activity = "Please choose your Downloads folder."
      return
    }

    do {
      let bookmark = try selectedURL.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      try activateFolder(selectedURL)
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
    } catch {
      activity = "Could not save folder access: \(error.localizedDescription)"
    }
  }

  private func startMonitoring() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.scanNow()
      }
    }
    scanNow()
  }

  private func restoreFolderAccess() -> Bool {
    guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
      return false
    }
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      guard isDownloads(url) else {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        return false
      }
      if isStale {
        let refreshed = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
      }
      try activateFolder(url)
      return true
    } catch {
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
      return false
    }
  }

  private func activateFolder(_ url: URL) throws {
    guard url.startAccessingSecurityScopedResource() else {
      throw CocoaError(.fileReadNoPermission)
    }
    let previousURL = securityScopedURL
    securityScopedURL = url
    previousURL?.stopAccessingSecurityScopedResource()
    downloadsURL = url
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let stateURL =
      applicationSupport
      .appending(path: "Image Autonamer", directoryHint: .isDirectory)
      .appending(path: "state.json")
    processor = ImageProcessor(
      directory: url,
      stateURL: stateURL,
      namer: OllamaClient(configuration: currentNamingConfiguration),
      reviewBeforeRenaming: reviewBeforeRenaming
    )
    hasFolderAccess = true
    recovery = nil
    activity = "Watching Downloads"
    startMonitoring()
    refreshReviews()
  }

  private func isDownloads(_ url: URL) -> Bool {
    url.resolvingSymlinksInPath().standardizedFileURL
      == defaultDownloadsURL.resolvingSymlinksInPath().standardizedFileURL
  }

  private func invalidateFolderAccess() {
    timer?.invalidate()
    timer = nil
    securityScopedURL?.stopAccessingSecurityScopedResource()
    securityScopedURL = nil
    downloadsURL = nil
    processor = nil
    pendingReviews = []
    renameHistory = []
    hasFolderAccess = false
    UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
  }

  private var currentNamingConfiguration: NamingConfiguration {
    NamingConfiguration(
      style: namingStyle,
      analysisContext: namingContext
    )
  }

  private func rebuildProcessor() {
    guard let url = downloadsURL else { return }
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let stateURL =
      applicationSupport
      .appending(path: "Image Autonamer", directoryHint: .isDirectory)
      .appending(path: "state.json")
    processor = ImageProcessor(
      directory: url,
      stateURL: stateURL,
      namer: OllamaClient(configuration: currentNamingConfiguration),
      reviewBeforeRenaming: reviewBeforeRenaming
    )
    refreshReviews()
  }

  private func performReviewAction(
    _ operation: @escaping @Sendable (ImageProcessor) async throws -> [ProcessingEvent]
  ) {
    guard !isApplyingReviews else { return }
    guard let processor else {
      reviewError = "Downloads access is required before reviewing files."
      return
    }
    isApplyingReviews = true
    reviewError = nil
    Task {
      do {
        let events = try await operation(processor)
        recentEvents = Array((events + recentEvents).prefix(8))
        if let failure = events.first(where: { $0.kind == .failed }) {
          reviewError = failure.message
          activity = failure.message
        } else if let event = events.last {
          activity = event.message
        }
      } catch {
        reviewError = error.localizedDescription
        activity = error.localizedDescription
      }
      let snapshot = await processor.reviewSnapshot()
      pendingReviews = snapshot.pending
      renameHistory = snapshot.history
      isApplyingReviews = false
    }
  }

  #if DEBUG
    private static func captureDemoDirectory() -> URL {
      FileManager.default.temporaryDirectory
        .appending(
          path: "image-autonamer-capture-demo-\(ProcessInfo.processInfo.processIdentifier)",
          directoryHint: .isDirectory
        )
    }

    private func configureCaptureDemo() {
      namingStyle = .documents
      namingContext = "Synthetic product demo documents"
      reviewBeforeRenaming = false
      launchAtLogin = true
      downloadsURL = defaultDownloadsURL
      hasFolderAccess = true
      activity = "Watching isolated demo folder"

      guard ProcessInfo.processInfo.arguments.contains("--capture-review"),
        let fixturePath = ProcessInfo.processInfo.environment["IMAGE_AUTONAMER_DEMO_FIXTURE"]
      else {
        return
      }

      let fileManager = FileManager.default
      let fixtureURL = URL(fileURLWithPath: fixturePath)
      do {
        try fileManager.createDirectory(
          at: defaultDownloadsURL,
          withIntermediateDirectories: true
        )
        for filename in ["123.pdf", "K-U-N-D-E-N-B-E-L-E-G.pdf"] {
          try fileManager.copyItem(
            at: fixtureURL,
            to: defaultDownloadsURL.appending(path: filename)
          )
        }
      } catch {
        activity = "Could not prepare demo: \(error.localizedDescription)"
        return
      }

      let stateURL = defaultDownloadsURL.appending(path: ".demo-state.json")
      let captureProcessor = ImageProcessor(
        directory: defaultDownloadsURL,
        stateURL: stateURL,
        namer: OllamaClient(configuration: currentNamingConfiguration),
        settleSeconds: 0
      )
      processor = captureProcessor
      activity = "Analyzing two synthetic PDFs locally…"
      isScanning = true
      Task {
        let events = await captureProcessor.scan(force: true)
        recentEvents = events
        let snapshot = await captureProcessor.reviewSnapshot()
        pendingReviews = snapshot.pending
        renameHistory = snapshot.history
        isScanning = false
        activity = "Synthetic demo ready"
      }
    }
  #endif
}
