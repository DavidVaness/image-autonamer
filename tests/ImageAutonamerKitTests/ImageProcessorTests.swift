import Foundation
import Testing

@testable import ImageAutonamerKit

private struct StaticNamer: ImageNaming {
  let name: String
  var evidence: [String] = []

  func suggest(for _: URL) async throws -> ImageNamingSuggestion {
    ImageNamingSuggestion(name: name, evidence: evidence)
  }
}

private struct FailingNamer: ImageNaming {
  let error: ImageAutonamerError

  func suggest(for _: URL) async throws -> ImageNamingSuggestion {
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
  #expect(await processor.reviewSnapshot().history.count == 1)
}

@Test
func reviewModeQueuesSuggestionWithoutRenaming() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor(
    namer: StaticNamer(name: "Orange Cat on Sofa", evidence: ["Subject: Orange cat"]),
    reviewBeforeRenaming: true
  )
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "IMG_0001.PNG")
  try Data("image".utf8).write(to: source)

  let events = await processor.scan()
  let snapshot = await processor.reviewSnapshot()

  #expect(events == [.init(kind: .queued, message: "Review orange-cat-on-sofa.png.")])
  #expect(FileManager.default.fileExists(atPath: source.path))
  #expect(snapshot.pending.count == 1)
  #expect(snapshot.pending[0].originalFilename == "IMG_0001.PNG")
  #expect(snapshot.pending[0].proposedFilename == "orange-cat-on-sofa.png")
  #expect(snapshot.pending[0].evidence == ["Subject: Orange cat"])
}

@Test
func approvingEditedSuggestionRenamesAndRecordsHistory() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor(reviewBeforeRenaming: true)
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "IMG_0001.PNG")
  try Data("image".utf8).write(to: source)
  _ = await processor.scan()
  let item = try #require(await processor.reviewSnapshot().pending.first)

  let event = try await processor.approveReview(id: item.id, editedStem: "Favorite Cat")
  let snapshot = await processor.reviewSnapshot()

  #expect(event.kind == .renamed)
  #expect(!FileManager.default.fileExists(atPath: source.path))
  #expect(
    FileManager.default.fileExists(
      atPath: fixture.directory.appending(path: "favorite-cat.png").path
    )
  )
  #expect(snapshot.pending.isEmpty)
  #expect(snapshot.history.count == 1)
  #expect(snapshot.history[0].originalFilename == "IMG_0001.PNG")
  #expect(snapshot.history[0].renamedFilename == "favorite-cat.png")
}

@Test
func rejectingSuggestionKeepsOriginalAndDoesNotQueueItAgain() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor(reviewBeforeRenaming: true)
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "IMG_0001.PNG")
  try Data("image".utf8).write(to: source)
  _ = await processor.scan()
  let item = try #require(await processor.reviewSnapshot().pending.first)

  let event = try await processor.rejectReview(id: item.id)
  let nextEvents = await processor.scan()

  #expect(event.kind == .rejected)
  #expect(FileManager.default.fileExists(atPath: source.path))
  #expect(nextEvents.isEmpty)
  #expect(await processor.reviewSnapshot().pending.isEmpty)
}

@Test
func undoRestoresOriginalFilenameWithoutCopying() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor()
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "IMG_0001.PNG")
  try Data("image".utf8).write(to: source)
  _ = await processor.scan()
  let record = try #require(await processor.reviewSnapshot().history.first)

  let event = try await processor.undoRename(id: record.id)
  let snapshot = await processor.reviewSnapshot()

  #expect(event.kind == .undone)
  #expect(FileManager.default.fileExists(atPath: source.path))
  #expect(!FileManager.default.fileExists(atPath: record.renamedPath))
  #expect(snapshot.history[0].canUndo == false)
}

@Test
func undoNeverOverwritesARecreatedOriginalFilename() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  let processor = fixture.processor()
  _ = await processor.scan()
  let source = fixture.directory.appending(path: "IMG_0001.PNG")
  try Data("renamed".utf8).write(to: source)
  _ = await processor.scan()
  let record = try #require(await processor.reviewSnapshot().history.first)
  try Data("new original".utf8).write(to: source)

  do {
    _ = try await processor.undoRename(id: record.id)
    Issue.record("Expected undo collision to fail")
  } catch let error as ImageAutonamerError {
    #expect(error.errorDescription?.contains("already exists") == true)
  }

  #expect(try Data(contentsOf: source) == Data("new original".utf8))
  #expect(try Data(contentsOf: URL(fileURLWithPath: record.renamedPath)) == Data("renamed".utf8))
}

@Test
func olderStateLoadsWithEmptyReviewCollections() async throws {
  let fixture = try Fixture(settleSeconds: 0)
  defer { fixture.remove() }
  try Data(#"{"didBaseline":true,"files":{}}"#.utf8).write(to: fixture.stateURL)

  let snapshot = await fixture.processor().reviewSnapshot()

  #expect(snapshot.pending.isEmpty)
  #expect(snapshot.history.isEmpty)
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

  func processor(
    namer: any ImageNaming = StaticNamer(name: "Orange Cat on Sofa"),
    reviewBeforeRenaming: Bool = false
  )
    -> ImageProcessor
  {
    ImageProcessor(
      directory: directory,
      stateURL: stateURL,
      namer: namer,
      reviewBeforeRenaming: reviewBeforeRenaming,
      settleSeconds: settleSeconds
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
