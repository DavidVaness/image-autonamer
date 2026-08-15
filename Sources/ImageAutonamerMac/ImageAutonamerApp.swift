import AppKit
import CoreServices
import ImageAutonamerKit
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let controller = AppController()
  private var settingsWindowController: NSWindowController?

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
    settingsWindowController = nil
  }

  private func makeSettingsWindowController() -> NSWindowController {
    let content = AppSettingsView(
      controller: controller,
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
        showSettings: appDelegate.showSettings
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
    .alert("Process existing images?", isPresented: $showProcessAllConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Process All") {
        controller.scanNow(force: true)
      }
    } message: {
      Text(
        "This renames every supported image currently in Downloads. New images are processed automatically without this step."
      )
    }
  }

  private func symbol(for kind: ProcessingEvent.Kind) -> String {
    switch kind {
    case .baseline: "shield.checkered"
    case .renamed: "checkmark.circle.fill"
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
  let closeSettings: () -> Void
  @State private var selectedTab = Tab.general

  var body: some View {
    TabView(selection: $selectedTab) {
      GeneralSettingsView(controller: controller)
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
          Text("The app keeps running in the menu bar and checks for new images every 15 seconds.")
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
    .alert("Process existing images?", isPresented: $showProcessAllConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Process All") {
        controller.scanNow(force: true)
      }
    } message: {
      Text(
        "This renames every supported image currently in Downloads. New images are processed automatically without this step."
      )
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
                Text("Preview analyzes one image without renaming or moving it.")
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
