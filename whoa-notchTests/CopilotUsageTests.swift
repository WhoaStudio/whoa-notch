import XCTest

@testable import whoa_notch

@MainActor
final class CopilotUsageTests: XCTestCase {

  func testParsesPremiumInteractionUsageAndResetDate() throws {
    let data = Data(
      """
      {
        "quota_reset_date_utc": "2026-11-01T00:00:00.000Z",
        "quota_snapshots": {
          "premium_interactions": {
            "percent_remaining": 57.0
          }
        }
      }
      """.utf8
    )

    let snapshot = try CopilotUsageService.parse(data)

    XCTAssertEqual(snapshot.premiumInteractions.percentage, 43)
    XCTAssertEqual(snapshot.monthlyReset, ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
  }

  func testRejectsPayloadWithoutPremiumQuota() {
    let data = Data(#"{"quota_snapshots": {}}"#.utf8)

    XCTAssertThrowsError(try CopilotUsageService.parse(data)) { error in
      guard case CopilotUsageServiceError.unrecognizedPayload = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }
}
