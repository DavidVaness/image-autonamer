import AppKit
import Foundation
import PDFKit
import Testing

@testable import ImageAutonamerKit

@Test
func missingModelResponseIsRecoverable() {
  let error = OllamaClient.responseError(
    statusCode: 404,
    message: "model not found",
    model: "qwen3-vl:4b"
  )

  guard case .modelUnavailable(let model) = error else {
    Issue.record("Expected a missing-model error")
    return
  }
  #expect(model == "qwen3-vl:4b")
}

@Test
func modelRuntimeFailureIsNotMisreportedAsMissing() {
  let error = OllamaClient.responseError(
    statusCode: 500,
    message: "model runner unexpectedly stopped",
    model: "qwen3-vl:4b"
  )

  guard case .ollamaError(let message) = error else {
    Issue.record("Expected a general Ollama error")
    return
  }
  #expect(message.contains("runner unexpectedly stopped"))
}

@Test
func pdfInputRendersOnlyTheFirstThreePagesAsPNGs() throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "image-autonamer-pdf-test-\(UUID().uuidString)", directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let pdfURL = directory.appending(path: "four-pages.pdf")
  let document = PDFDocument()

  for index in 0..<4 {
    let image = NSImage(size: NSSize(width: 240, height: 320))
    image.lockFocus()
    NSColor(calibratedWhite: CGFloat(index + 1) / 5, alpha: 1).setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    let page = try #require(PDFPage(image: image))
    document.insert(page, at: index)
  }
  #expect(document.write(to: pdfURL))

  let inputs = try OllamaClient.portableInputData(from: pdfURL)

  #expect(inputs.count == 3)
  let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  #expect(inputs.allSatisfy { $0.starts(with: pngSignature) })
}

@Test
func checkedInPDFFixtureUsesEmbeddedTextBeforeOCR() throws {
  let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "eval/fixtures/north-star-invoice.pdf")
  let renderedPages = try OllamaClient.portableInputData(from: fixture)

  let evidence = try #require(
    DocumentTextExtractor.extract(from: fixture, renderedPages: renderedPages)
  )

  #expect(evidence.source == .embedded)
  #expect(evidence.text.contains("INV-2048"))
  #expect(evidence.text.contains("NORTH STAR STUDIO"))
}

@Test @MainActor
func scannedPDFUsesLocalVisionOCRFallback() throws {
  _ = NSApplication.shared
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "image-autonamer-ocr-test-\(UUID().uuidString)", directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let pdfURL = directory.appending(path: "scan.pdf")
  let image = NSImage(size: NSSize(width: 1400, height: 900))
  image.lockFocus()
  NSColor.white.setFill()
  NSRect(origin: .zero, size: image.size).fill()
  NSString(string: "NORTH STAR SCAN\nINVOICE INV-9090\nISSUE DATE 2026-08-17")
    .draw(
      in: NSRect(x: 100, y: 300, width: 1200, height: 420),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 72, weight: .bold),
        .foregroundColor: NSColor.black,
      ]
    )
  image.unlockFocus()
  let document = PDFDocument()
  document.insert(try #require(PDFPage(image: image)), at: 0)
  #expect(document.write(to: pdfURL))
  let renderedPages = try OllamaClient.portableInputData(from: pdfURL)

  let evidence = try #require(
    DocumentTextExtractor.extract(from: pdfURL, renderedPages: renderedPages)
  )

  #expect(evidence.source == .visionOCR)
  #expect(evidence.text.contains("INV-9090"))
  #expect(evidence.text.contains("2026-08-17"))
}
