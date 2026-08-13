import Foundation
import Testing

@testable import ImageAutonamerKit

@Test
func descriptiveStyleUsesOnlyTheVisualDescription() {
  let analysis = ImageNamingAnalysis(
    description: "quarterly revenue dashboard",
    organization: "Acme",
    organizationVisible: true,
    documentType: "report"
  )

  let result = ImageNameComposer.compose(
    analysis: analysis,
    configuration: NamingConfiguration(style: .descriptive),
    imageDate: Date(timeIntervalSince1970: 0)
  )

  #expect(result == "quarterly revenue dashboard")
}

@Test
func dateStyleUsesSortableYearMonthDayPrefix() throws {
  let date = try #require(
    ISO8601DateFormatter().date(from: "2026-08-11T12:00:00Z")
  )
  let analysis = ImageNamingAnalysis(
    description: "red mug beside laptop",
    organization: "",
    organizationVisible: false,
    documentType: ""
  )

  let result = ImageNameComposer.compose(
    analysis: analysis,
    configuration: NamingConfiguration(style: .dateDescriptive),
    imageDate: date
  )

  #expect(result == "2026-08-11 red mug beside laptop")
}

@Test
func dateStyleFallsBackCleanlyWhenNoDateExists() {
  let analysis = ImageNamingAnalysis(
    description: "mountain lake at sunset",
    organization: "",
    organizationVisible: false,
    documentType: ""
  )

  let result = ImageNameComposer.compose(
    analysis: analysis,
    configuration: NamingConfiguration(style: .dateDescriptive),
    imageDate: nil
  )

  #expect(result == "mountain lake at sunset")
}

@Test
func businessStyleUsesCanonicalVisibleOrganizationAndDocumentType() {
  let analysis = ImageNamingAnalysis(
    description: "annual software renewal",
    organization: "northwind labs",
    organizationVisible: true,
    documentType: "invoice"
  )
  let configuration = NamingConfiguration(
    style: .businessDocument,
    knownOrganizations: ["Northwind Labs"]
  )

  let result = ImageNameComposer.compose(
    analysis: analysis,
    configuration: configuration,
    imageDate: nil
  )

  #expect(result == "northwind labs invoice annual software renewal")
}

@Test
func businessStyleRejectsUnsupportedOrganizationGuess() {
  let analysis = ImageNamingAnalysis(
    description: "annual software renewal",
    organization: "Northwind Labs",
    organizationVisible: false,
    documentType: "invoice"
  )

  let result = ImageNameComposer.compose(
    analysis: analysis,
    configuration: NamingConfiguration(style: .businessDocument),
    imageDate: nil
  )

  #expect(result == "invoice annual software renewal")
}

@Test
func businessStyleRemovesOverlappingModelPhrases() {
  let analysis = ImageNamingAnalysis(
    description: "cafe receipt with items and total",
    organization: "North Star Cafe",
    organizationVisible: true,
    documentType: "receipt"
  )

  let result = ImageNameComposer.compose(
    analysis: analysis,
    configuration: NamingConfiguration(style: .businessDocument),
    imageDate: nil
  )

  #expect(result == "north star cafe receipt with items and total")
}

@Test
func organizationVocabularyIsBoundedAndDeduplicated() {
  let configuration = NamingConfiguration(
    knownOrganizations: [" Acme ", "acme", "Northwind\nLabs", ""]
  )

  #expect(configuration.knownOrganizations == ["Acme", "Northwind Labs"])
}
