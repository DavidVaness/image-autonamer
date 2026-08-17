import Testing

@testable import ImageAutonamerKit

@Test
func normalizesModelOutput() throws {
  #expect(
    try FilenameSanitizer.slugify("  Café: Cat & Croissant.PNG  ")
      == "cafe-cat-croissant"
  )
}

@Test
func limitsWords() throws {
  #expect(
    try FilenameSanitizer.slugify("one two three four five", maxWords: 3)
      == "one-two-three"
  )
}

@Test
func removesPDFExtensionReturnedByModel() throws {
  #expect(
    try FilenameSanitizer.slugify("North Star invoice.pdf")
      == "north-star-invoice"
  )
}

@Test
func rejectsEmptyOutput() {
  #expect(throws: ImageAutonamerError.self) {
    try FilenameSanitizer.slugify("💥")
  }
}
