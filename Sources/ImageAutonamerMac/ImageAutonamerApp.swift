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

      Button(controller.hasFolderAccess ? "Reauthorize Downloads…" : "Choose Downloads…") {
        controller.chooseDownloads()
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
}
