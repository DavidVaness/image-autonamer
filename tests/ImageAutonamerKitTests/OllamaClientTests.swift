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
