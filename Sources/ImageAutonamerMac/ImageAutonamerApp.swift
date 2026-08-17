import AppKit
import CoreServices
import ImageAutonamerKit
import PDFKit
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let controller = AppController()
  private var settingsWindowController: NSWindowController?
  private var reviewWindowController: NSWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !launchedAsLoginItem else { return }
    DispatchQueue.main.async {
      self.showSettings()
    }
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showSettings()
    return true
  }

  func showSettings() {
    let windowController = settingsWindowController ?? makeSettingsWindowController()
    settingsWindowController = windowController
    windowController.showWindow(nil)
    windowController.window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if window === settingsWindowController?.window {
      settingsWindowController = nil
    }
    if window === reviewWindowController?.window {
      reviewWindowController = nil
    }
  }

  func showReviewInbox() {
    let windowController = reviewWindowController ?? makeReviewWindowController()
    reviewWindowController = windowController
    controller.refreshReviews()
    windowController.showWindow(nil)
    windowController.window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func makeSettingsWindowController() -> NSWindowController {
    let content = AppSettingsView(
      controller: controller,
      showReviewInbox: showReviewInbox,
      closeSettings: { [weak self] in
        self?.settingsWindowController?.close()
      }
    )
    let hostingController = NSHostingController(rootView: content)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Image Autonamer Settings"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.setContentSize(NSSize(width: 550, height: 560))
    window.center()
    window.isReleasedWhenClosed = true
    window.tabbingMode = .disallowed
    window.delegate = self
    return NSWindowController(window: window)
  }

  private func makeReviewWindowController() -> NSWindowController {
    let hostingController = NSHostingController(
      rootView: ReviewInboxView(controller: controller)
    )
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Review Inbox"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(NSSize(width: 820, height: 600))
    window.minSize = NSSize(width: 680, height: 460)
    window.center()
    window.isReleasedWhenClosed = true
    window.tabbingMode = .disallowed
    window.delegate = self
    return NSWindowController(window: window)
  }

  private var launchedAsLoginItem: Bool {
    NSAppleEventManager.shared().currentAppleEvent?
      .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
  }
}

@main
struct ImageAutonamerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuContent(
        controller: appDelegate.controller,
        showSettings: appDelegate.showSettings,
        showReviewInbox: appDelegate.showReviewInbox
      )
    } label: {
      Label("Image Autonamer", systemImage: "photo.badge.checkmark")
    }
    .menuBarExtraStyle(.window)
  }
}

private struct MenuContent: View {
  @ObservedObject var controller: AppController
  let showSettings: () -> Void
  let showReviewInbox: () -> Void
  @State private var showProcessAllConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 9) {
        Image(systemName: controller.isScanning ? "sparkles" : "eye.fill")
          .foregroundStyle(controller.isScanning ? .purple : .green)
        VStack(alignment: .leading, spacing: 2) {
          Text("Image Autonamer")
            .font(.headline)
          Text(controller.activity)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      Divider()

      if !controller.recentEvents.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("Recent activity")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(Array(controller.recentEvents.enumerated()), id: \.offset) { _, event in
            Label(event.message, systemImage: symbol(for: event.kind))
              .font(.caption)
              .lineLimit(2)
          }
        }
        Divider()
      }

      if let recovery = controller.recovery, recovery != .reauthorizeFolder {
        Button(recoveryLabel(for: recovery)) {
          controller.performRecovery()
        }
        .buttonStyle(.borderedProminent)
      }

      GroupBox {
        HStack(spacing: 10) {
          Image(
            systemName: controller.hasFolderAccess
              ? "checkmark.circle.fill" : "xmark.circle.fill"
          )
          .foregroundStyle(controller.hasFolderAccess ? .green : .red)
          VStack(alignment: .leading, spacing: 2) {
            Text("Downloads Access")
              .font(.callout.weight(.semibold))
            Text(controller.hasFolderAccess ? "Granted" : "Required for automatic renaming")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if controller.hasFolderAccess {
            Button("Reauthorize…") {
              controller.chooseDownloads()
            }
          } else {
            Button("Grant Access") {
              controller.chooseDownloads()
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }

      GroupBox {
        HStack(spacing: 10) {
          Image(systemName: "tray.full.fill")
            .foregroundStyle(controller.pendingReviews.isEmpty ? Color.secondary : Color.orange)
          VStack(alignment: .leading, spacing: 2) {
            Text("Review Inbox")
              .font(.callout.weight(.semibold))
            Text(
              controller.pendingReviews.isEmpty
                ? "No suggestions waiting" : "\(controller.pendingReviews.count) waiting"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Open…") {
            showReviewInbox()
          }
        }
      }

      GroupBox {
        HStack(spacing: 10) {
          Image(systemName: "textformat")
            .foregroundStyle(.purple)
          VStack(alignment: .leading, spacing: 2) {
            Text("Naming")
              .font(.callout.weight(.semibold))
            Text(controller.namingStyle.title)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Configure…") {
            showSettings()
          }
        }
      }

      Toggle(
        "Launch at Login",
        isOn: Binding(
          get: { controller.launchAtLogin },
          set: { controller.setLaunchAtLogin($0) }
        )
      )

      Toggle(
        "Review Before Renaming",
        isOn: Binding(
          get: { controller.reviewBeforeRenaming },
          set: { controller.setReviewBeforeRenaming($0) }
        )
      )
      .disabled(controller.isScanning || controller.isApplyingReviews)

      HStack {
        Button("Scan Now") {
          controller.scanNow()
        }
        .disabled(controller.isScanning || !controller.hasFolderAccess)

        Button("Open Downloads") {
          controller.openDownloads()
        }
        .disabled(!controller.hasFolderAccess)
      }

      Button("Process Existing Images…") {
        showProcessAllConfirmation = true
      }
      .disabled(controller.isScanning || !controller.hasFolderAccess)

      Divider()

      HStack {
        Text("Local model: qwen3-vl:4b")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(14)
    .frame(width: 340)
    .alert("Process existing files?", isPresented: $showProcessAllConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Process All") {
        controller.scanNow(force: true)
      }
    } message: {
      Text(
        "This renames every supported image or PDF currently in Downloads. New files are processed automatically without this step."
      )
    }
  }

  private func symbol(for kind: ProcessingEvent.Kind) -> String {
    switch kind {
    case .baseline: "shield.checkered"
    case .queued: "tray.full.fill"
    case .renamed: "checkmark.circle.fill"
    case .rejected: "hand.raised.fill"
    case .undone: "arrow.uturn.backward.circle.fill"
    case .skipped: "minus.circle"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  private func recoveryLabel(for recovery: ProcessingEvent.Recovery) -> String {
    switch recovery {
    case .installOllama: "Open Ollama Setup"
    case .pullModel: "Copy Model Install Command"
    case .reauthorizeFolder: "Reauthorize Downloads"
    }
  }
}

private struct AppSettingsView: View {
  private enum Tab: Hashable {
    case general
    case naming
  }

  @ObservedObject var controller: AppController
  let showReviewInbox: () -> Void
  let closeSettings: () -> Void
  @State private var selectedTab = Tab.general

  var body: some View {
    TabView(selection: $selectedTab) {
      GeneralSettingsView(controller: controller, showReviewInbox: showReviewInbox)
        .tabItem {
          Label("General", systemImage: "gearshape")
        }
        .tag(Tab.general)

      NamingSettingsView(controller: controller, closeSettings: closeSettings)
        .tabItem {
          Label("Naming", systemImage: "textformat")
        }
        .tag(Tab.naming)
    }
    .frame(width: 550, height: 560)
  }
}

private struct GeneralSettingsView: View {
  @ObservedObject var controller: AppController
  let showReviewInbox: () -> Void
  @State private var showProcessAllConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 5) {
        Text("General Settings")
          .font(.title2.weight(.semibold))
        Text("Control folder access, automatic startup, and scanning.")
          .foregroundStyle(.secondary)
      }

      GroupBox("Downloads Access") {
        HStack(spacing: 12) {
          Image(
            systemName: controller.hasFolderAccess
              ? "checkmark.circle.fill" : "xmark.circle.fill"
          )
          .font(.title2)
          .foregroundStyle(controller.hasFolderAccess ? .green : .red)

          VStack(alignment: .leading, spacing: 3) {
            Text(controller.hasFolderAccess ? "Access granted" : "Access required")
              .font(.headline)
            Text(
              controller.hasFolderAccess
                ? "Image Autonamer can monitor your selected Downloads folder."
                : "Choose Downloads once to enable automatic renaming."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }

          Spacer()

          if controller.hasFolderAccess {
            Button("Reauthorize…") {
              controller.chooseDownloads()
            }
          } else {
            Button("Grant Access") {
              controller.chooseDownloads()
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .padding(6)
      }

      GroupBox("Automation") {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            "Launch Image Autonamer at login",
            isOn: Binding(
              get: { controller.launchAtLogin },
              set: { controller.setLaunchAtLogin($0) }
            )
          )
          Text(
            "The app keeps running in the menu bar and checks for new images and PDFs every 15 seconds."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Divider()
          HStack {
            Toggle(
              "Review suggestions before renaming",
              isOn: Binding(
                get: { controller.reviewBeforeRenaming },
                set: { controller.setReviewBeforeRenaming($0) }
              )
            )
            .disabled(controller.isScanning || controller.isApplyingReviews)
            Spacer()
            Button("Open Inbox…") {
              showReviewInbox()
            }
          }
          Text(
            "When enabled, every new file waits for approval. Ambiguous PDF improvements are always queued."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
      }

      GroupBox("Run Manually") {
        VStack(alignment: .leading, spacing: 10) {
          Text(controller.activity)
            .font(.callout)
            .foregroundStyle(.secondary)
          HStack {
            Button("Scan Now") {
              controller.scanNow()
            }
            .disabled(controller.isScanning || !controller.hasFolderAccess)

            Button("Process Existing Images…") {
              showProcessAllConfirmation = true
            }
            .disabled(controller.isScanning || !controller.hasFolderAccess)

            Spacer()

            Button("Open Downloads") {
              controller.openDownloads()
            }
            .disabled(!controller.hasFolderAccess)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
      }

      Spacer()
    }
    .padding(24)
    .alert("Process existing files?", isPresented: $showProcessAllConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Process All") {
        controller.scanNow(force: true)
      }
    } message: {
      Text(
        "This renames every supported image or PDF currently in Downloads. New files are processed automatically without this step."
      )
    }
  }
}

private struct ReviewInboxView: View {
  private enum Section: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case history = "History"

    var id: Self { self }
  }

  @ObservedObject var controller: AppController
  @State private var section = Section.pending
  @State private var draftStems: [UUID: String] = [:]

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Review Inbox")
            .font(.title.weight(.semibold))
          Text("Verify local AI suggestions before they touch your filenames.")
            .foregroundStyle(.secondary)
        }

        Spacer()

        Picker("Section", selection: $section) {
          Text("Pending \(controller.pendingReviews.count)").tag(Section.pending)
          Text("History \(controller.renameHistory.count)").tag(Section.history)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 250)
      }
      .padding(20)

      Divider()

      Group {
        switch section {
        case .pending:
          pendingContent
        case .history:
          historyContent
        }
      }

      if let error = controller.reviewError {
        Divider()
        HStack {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
          Spacer()
          Button("Dismiss") {
            controller.clearReviewError()
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
      }
    }
    .frame(minWidth: 680, minHeight: 460)
    .onAppear {
      controller.refreshReviews()
      synchronizeDrafts()
    }
    .onChange(of: controller.pendingReviews) { _ in
      synchronizeDrafts()
    }
  }

  @ViewBuilder
  private var pendingContent: some View {
    if controller.pendingReviews.isEmpty {
      emptyState(
        icon: "checkmark.circle",
        title: "Inbox clear",
        message: !controller.hasFolderAccess
          ? "Grant Downloads access in General Settings to review suggestions."
          : controller.reviewBeforeRenaming
            ? "New image and PDF suggestions will appear here before renaming."
            : "Ambiguous PDF improvements appear here automatically. Enable review to hold every suggestion."
      )
    } else {
      VStack(spacing: 0) {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(controller.pendingReviews) { item in
              pendingRow(item)
              Divider()
                .padding(.leading, 112)
            }
          }
        }

        Divider()

        HStack {
          Text("Files stay unchanged until you approve them.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          if controller.isApplyingReviews {
            ProgressView()
              .controlSize(.small)
          }
          Button("Approve All (\(controller.pendingReviews.count))") {
            controller.approveAllReviews(editedStems: draftStems)
          }
          .buttonStyle(.borderedProminent)
          .disabled(controller.isApplyingReviews)
        }
        .padding(16)
      }
    }
  }

  @ViewBuilder
  private var historyContent: some View {
    if controller.renameHistory.isEmpty {
      emptyState(
        icon: "clock.arrow.circlepath",
        title: "No rename history",
        message: "Approved and automatic renames will appear here with an undo action."
      )
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(controller.renameHistory) { record in
            historyRow(record)
            Divider()
              .padding(.leading, 28)
          }
        }
      }
    }
  }

  private func pendingRow(_ item: ReviewItem) -> some View {
    HStack(alignment: .top, spacing: 16) {
      thumbnail(for: item.sourceURL)

      VStack(alignment: .leading, spacing: 8) {
        Text(item.originalFilename)
          .font(.headline)
          .lineLimit(1)
          .help(item.sourcePath)

        HStack(spacing: 6) {
          TextField("Proposed filename", text: draftBinding(for: item))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Proposed filename for \(item.originalFilename)")
          Text(".\(item.sourceURL.pathExtension.lowercased())")
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
        }

        if !item.evidence.isEmpty {
          Label(item.evidence.joined(separator: "  ·  "), systemImage: "eye")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      VStack(alignment: .trailing, spacing: 8) {
        Button("Approve") {
          controller.approveReview(
            id: item.id,
            editedStem: draftStems[item.id] ?? item.proposedStem
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(controller.isApplyingReviews)

        Button("Keep Original") {
          controller.rejectReview(id: item.id)
        }
        .disabled(controller.isApplyingReviews)

        Button("Show in Finder") {
          controller.revealReviewItem(item)
        }
      }
      .frame(width: 112, alignment: .trailing)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private func historyRow(_ record: RenameRecord) -> some View {
    HStack(spacing: 14) {
      Image(systemName: record.canUndo ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
        .font(.title2)
        .foregroundStyle(record.canUndo ? Color.green : Color.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(record.renamedFilename)
          .font(.headline)
          .lineLimit(1)
        Text(
          "From \(record.originalFilename) · \(record.renamedAt.formatted(date: .abbreviated, time: .shortened))"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        if record.undoneAt != nil {
          Text("Restored to the original filename")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button("Show in Finder") {
        controller.revealRenameRecord(record)
      }

      Button("Undo") {
        controller.undoRename(id: record.id)
      }
      .disabled(!record.canUndo || controller.isApplyingReviews)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private func thumbnail(for url: URL) -> some View {
    Group {
      if let image = previewImage(for: url) {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "photo")
          .font(.title)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 76, height: 64)
    .background(.quaternary.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityLabel("Preview of \(url.lastPathComponent)")
  }

  private func previewImage(for url: URL) -> NSImage? {
    if url.pathExtension.lowercased() == "pdf" {
      guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
      return page.thumbnail(of: NSSize(width: 152, height: 128), for: .mediaBox)
    }
    return NSImage(contentsOf: url)
  }

  private func emptyState(icon: String, title: String, message: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 42, weight: .light))
        .foregroundStyle(.secondary)
      Text(title)
        .font(.title2.weight(.semibold))
      Text(message)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
  }

  private func draftBinding(for item: ReviewItem) -> Binding<String> {
    Binding(
      get: { draftStems[item.id] ?? item.proposedStem },
      set: { draftStems[item.id] = $0 }
    )
  }

  private func synchronizeDrafts() {
    let currentIDs = Set(controller.pendingReviews.map(\.id))
    draftStems = draftStems.filter { currentIDs.contains($0.key) }
    for item in controller.pendingReviews where draftStems[item.id] == nil {
      draftStems[item.id] = item.proposedStem
    }
  }
}

private struct NamingSettingsView: View {
  @ObservedObject var controller: AppController
  let closeSettings: () -> Void
  @State private var style: NamingStyle
  @State private var namingContext: String

  init(controller: AppController, closeSettings: @escaping () -> Void) {
    self.controller = controller
    self.closeSettings = closeSettings
    _style = State(initialValue: controller.namingStyle)
    _namingContext = State(initialValue: controller.namingContext)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 5) {
            Text("Naming Settings")
              .font(.title2.weight(.semibold))
            Text("Choose what a useful filename means for your workflow.")
              .foregroundStyle(.secondary)
          }

          Picker("Style", selection: $style) {
            ForEach(NamingStyle.allCases, id: \.self) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.radioGroup)

          Text(style.explanation)
            .font(.callout)
            .foregroundStyle(.secondary)

          if style == .documents {
            GroupBox("Automatic document structure") {
              VStack(alignment: .leading, spacing: 10) {
                Label(
                  "The correspondent is inferred from the visible issuer, sender, or merchant.",
                  systemImage: "building.2"
                )
                .font(.callout)

                Divider()

                documentRecipe(
                  type: "Invoice",
                  recipe: "date · correspondent · invoice · reference · title"
                )
                documentRecipe(
                  type: "Statement",
                  recipe: "period · correspondent · statement · reference · title"
                )
                documentRecipe(
                  type: "Receipt",
                  recipe: "date · merchant · receipt · title"
                )
                documentRecipe(
                  type: "Other",
                  recipe: "date · correspondent · document · title"
                )

                Text(
                  "Also detects contracts, letters, reports, certificates, and tax documents. Missing or ambiguous fields are omitted."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(6)
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("Naming context")
                .font(.headline)
              Spacer()
              Text("\(namingContext.count)/500")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            TextEditor(text: $namingContext)
              .font(.body)
              .frame(height: 68)
              .padding(5)
              .background(.background)
              .clipShape(RoundedRectangle(cornerRadius: 6))
              .overlay {
                RoundedRectangle(cornerRadius: 6)
                  .stroke(.quaternary)
              }
            Text(
              style == .documents
                ? "Optional domain guidance, for example: German consulting invoices and tax letters. Correspondents still must be visible."
                : "Optional guidance, for example: Product screenshots for a pottery shop. Stored locally and sent only to Ollama."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          GroupBox {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Button("Preview with Image…") {
                  controller.previewImage(
                    style: style,
                    namingContext: namingContext
                  )
                }
                .disabled(controller.isPreviewing)
                if controller.isPreviewing {
                  ProgressView()
                    .controlSize(.small)
                  Text("Analyzing locally…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              if let result = controller.previewResult {
                Label(result, systemImage: "checkmark.circle.fill")
                  .font(.caption)
                  .foregroundStyle(.green)
                  .textSelection(.enabled)
              }
              if let error = controller.previewError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption)
                  .foregroundStyle(.red)
              }
              if controller.previewResult == nil && controller.previewError == nil
                && !controller.isPreviewing
              {
                Text("Preview analyzes one image or PDF without renaming or moving it.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack {
        Spacer()
        Button("Cancel") {
          closeSettings()
        }
        .keyboardShortcut(.cancelAction)
        Button("Save") {
          controller.saveNamingSettings(
            style: style,
            namingContext: namingContext
          )
          closeSettings()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: style) { _ in
      controller.clearPreview()
    }
    .onChange(of: namingContext) { value in
      if value.count > 500 {
        namingContext = String(value.prefix(500))
      }
      controller.clearPreview()
    }
    .onDisappear {
      controller.cancelPreview()
    }
  }

  private func documentRecipe(type: String, recipe: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(type)
        .font(.callout.weight(.semibold))
        .frame(width: 72, alignment: .leading)
      Text(recipe)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }
  }
}
