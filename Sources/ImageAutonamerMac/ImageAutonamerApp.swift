import AppKit
import ImageAutonamerKit
import SwiftUI

@main
struct ImageAutonamerApp: App {
  @StateObject private var controller = AppController()

  var body: some Scene {
    MenuBarExtra {
      MenuContent(controller: controller)
    } label: {
      Label("Image Autonamer", systemImage: "photo.badge.checkmark")
    }
    .menuBarExtraStyle(.window)
  }
}

private struct MenuContent: View {
  @ObservedObject var controller: AppController
  @State private var showProcessAllConfirmation = false
  @State private var showNamingSettings = false

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
            showNamingSettings = true
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
    .sheet(isPresented: $showNamingSettings) {
      NamingSettingsView(controller: controller)
    }
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

private struct NamingSettingsView: View {
  @ObservedObject var controller: AppController
  @Environment(\.dismiss) private var dismiss
  @State private var style: NamingStyle
  @State private var organizationVocabulary: String
  @State private var namingContext: String

  init(controller: AppController) {
    self.controller = controller
    _style = State(initialValue: controller.namingStyle)
    _organizationVocabulary = State(initialValue: controller.organizationVocabulary)
    _namingContext = State(initialValue: controller.namingContext)
  }

  var body: some View {
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

      if style == .businessDocument {
        VStack(alignment: .leading, spacing: 6) {
          Text("Known organizations")
            .font(.headline)
          TextField("Example & Co., Cedar Labs", text: $organizationVocabulary)
            .textFieldStyle(.roundedBorder)
          Text(
            "Optional, comma-separated spelling hints. A name is used only when it is visibly supported in the image."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
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
          "Optional guidance, for example: Product screenshots for a pottery shop. Stored locally and sent only to Ollama."
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
                organizationVocabulary: organizationVocabulary,
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

      Spacer()

      HStack {
        Spacer()
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Button("Save") {
          controller.saveNamingSettings(
            style: style,
            organizationVocabulary: organizationVocabulary,
            namingContext: namingContext
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(22)
    .frame(width: 500, height: style == .businessDocument ? 560 : 490)
    .onChange(of: style) { _ in
      controller.clearPreview()
    }
    .onChange(of: organizationVocabulary) { _ in
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
}
