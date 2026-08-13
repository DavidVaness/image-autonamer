import Foundation
import Testing

@testable import ImageAutonamerKit

private struct StaticNamer: ImageNaming {
  let name: String

  func suggestName(for _: URL) async throws -> String {
    name
  }
}

private struct FailingNamer: ImageNaming {
  let error: ImageAutonamerError

  func suggestName(for _: URL) async throws -> String {
    throw error
  }
}

@Test
func firstScanProtectsExistingImages() async throws {
  let fixture = try Fixture()
  defer { fixture.remove() }
  let existing = fixture.directory.appending(path: "existing.png")
  try Data("image".utf8).write(to: existing)
  let processor = fixture.processor()

  let events = await processor.scan()

  #expect(events == [.init(kind: .baseline, message: "Protected 1 existing image(s).")])
  #expect(FileManager.default.fileExists(atPath: existing.path))
}

@Test
func newImageIsRenamedAfterBaseline() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor()
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "IMG_0001.PNG")
  try Data("image".utf8).write(to: source)

  let events = await processor.scan()

  #expect(events.count == 1)
  #expect(events[0].kind == .renamed)
  #expect(!FileManager.default.fileExists(atPath: source.path))
  #expect(
    FileManager.default.fileExists(
      atPath: fixture.directory.appending(path: "orange-cat-on-sofa.png").path
    )
  )
}

@Test
func collisionDoesNotOverwriteExistingFile() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor()
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "download.png")
  let existing = fixture.directory.appending(path: "orange-cat-on-sofa.png")
  try Data("new".utf8).write(to: source)
  try Data("existing".utf8).write(to: existing)

  _ = await processor.scan()

  #expect(try Data(contentsOf: existing) == Data("existing".utf8))
  #expect(
    FileManager.default.fileExists(
      atPath: fixture.directory.appending(path: "orange-cat-on-sofa-2.png").path
    )
  )
}

@Test
func missingModelOffersARecoveryAction() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor(
    namer: FailingNamer(error: .modelUnavailable("qwen3-vl:4b"))
  )
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "download.png")
  try Data("image".utf8).write(to: source)

  let events = await processor.scan()

  #expect(events.count == 1)
  #expect(events[0].kind == .failed)
  #expect(events[0].recovery == .pullModel("qwen3-vl:4b"))
  #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test
func unavailableOllamaOffersSetupWithoutChangingTheFile() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor(namer: FailingNamer(error: .ollamaUnavailable))
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "download.png")
  try Data("image".utf8).write(to: source)

  let events = await processor.scan()

  #expect(events.count == 1)
  #expect(events[0].recovery == .installOllama)
  #expect(FileManager.default.fileExists(atPath: source.path))
}

private struct Fixture: Sendable {
  let root: URL
  let directory: URL
  let stateURL: URL
  let settleSeconds: TimeInterval

  init(settleSeconds: TimeInterval = 15) throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "image-autonamer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    directory = root.appending(path: "Downloads", directoryHint: .isDirectory)
    stateURL = root.appending(path: "state.json")
    self.settleSeconds = settleSeconds
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func processor(namer: any ImageNaming = StaticNamer(name: "Orange Cat on Sofa"))
    -> ImageProcessor
  {
    ImageProcessor(
      directory: directory,
      stateURL: stateURL,
      namer: namer,
      settleSeconds: settleSeconds
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
