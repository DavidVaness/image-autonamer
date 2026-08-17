import Testing

@testable import ImageAutonamerKit

@Test
func genericNumericFilenameIsRenamedWhenProposalAddsVisibleSignal() {
  let decision = DocumentFilenameDecisionEngine.evaluate(
    originalFilename: "123.pdf",
    proposedName: "security personnel building entrances",
    extractedText: "Security personnel in uniform walking through building entrances and exits"
  )

  #expect(decision.disposition == .rename)
}

@Test
func richFilenameIsKeptWhenProposalDropsVisibleDateAndReference() {
  let decision = DocumentFilenameDecisionEngine.evaluate(
    originalFilename: "2025-10-03 Ertragsabrechnung REF FUND42.pdf",
    proposedName: "dkb statement of account",
    extractedText: "North Bank Ertragsabrechnung REF FUND42 vom 2025-10-03 statement of account"
  )

  #expect(decision.disposition == .keep)
  #expect(decision.reason.contains("discard"))
}

@Test
func specificSourceLanguageFilenameBeatsGenericTranslation() {
  let decision = DocumentFilenameDecisionEngine.evaluate(
    originalFilename: "Speisekarte Stand 10 2024.pdf",
    proposedName: "restaurant lunch menu",
    extractedText: "Speisekarte Stand 10 2024 Suppen Pasta Öffnungszeiten"
  )

  #expect(decision.disposition == .keep)
}

@Test
func ambiguousReceiptFilenameRequiresReview() {
  let decision = DocumentFilenameDecisionEngine.evaluate(
    originalFilename: "-K-U-N-D-E-N-B-E-L-E-G-.pdf",
    proposedName: "db ticket machine payment receipt",
    extractedText: "DB Kundenbeleg Fahrkartenautomat Zahlung receipt"
  )

  #expect(decision.disposition == .review)
}

@Test
func proposalCanRenameWhenItPreservesAndAddsVisibleDetails() {
  let decision = DocumentFilenameDecisionEngine.evaluate(
    originalFilename: "north star invoice.pdf",
    proposedName: "2026 08 15 north star invoice inv 2048",
    extractedText: "North Star invoice INV 2048 issue date 2026 08 15"
  )

  #expect(decision.disposition == .rename)
}

@Test
func missingTextKeepsOriginalFilename() {
  let decision = DocumentFilenameDecisionEngine.evaluate(
    originalFilename: "document.pdf",
    proposedName: "annual renewal invoice",
    extractedText: nil
  )

  #expect(decision.disposition == .keep)
}
