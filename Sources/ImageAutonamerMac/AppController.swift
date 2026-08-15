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

  init() {
    defaultDownloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    if let rawStyle = UserDefaults.standard.string(forKey: Self.namingStyleKey) {
      namingStyle =
        rawStyle == "businessDocument"
        ? .documents : NamingStyle(rawValue: rawStyle) ?? .descriptive
    }
    namingContext = UserDefaults.standard.string(forKey: Self.namingContextKey) ?? ""
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
    activity = force ? "Processing existing images…" : "Checking Downloads…"
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
      if let failure = events.first(where: { $0.kind == .failed }) {
        if failure.recovery == .reauthorizeFolder {
          invalidateFolderAccess()
        }
        activity = failure.message
        recovery = failure.recovery
      } else if let rename = events.first(where: { $0.kind == .renamed }) {
        activity = rename.message
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
    panel.title = "Preview an image name"
    panel.message = "The selected image is analyzed locally and will not be renamed."
    panel.prompt = "Preview Name"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.image]

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
      namer: OllamaClient(configuration: currentNamingConfiguration)
    )
    hasFolderAccess = true
    recovery = nil
    activity = "Watching Downloads"
    startMonitoring()
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
      namer: OllamaClient(configuration: currentNamingConfiguration)
    )
  }
}
