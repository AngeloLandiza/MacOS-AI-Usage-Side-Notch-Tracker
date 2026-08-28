import Foundation
import Testing
@testable import SideNotch

@Suite struct GeminiSummaryParsingTests {
    static let fixture = Data("""
    {"groups": [
      {"buckets": [
        {"bucketId": "gemini-5h", "remainingFraction": 0.82, "resetTime": "2026-08-28T19:45:00Z"},
        {"bucketId": "gemini-weekly", "remainingFraction": 0.64, "resetTime": "2026-09-01T07:00:00Z"}
      ]},
      {"buckets": [
        {"bucketId": "3p-5h", "remainingFraction": 1.0, "resetTime": "2026-08-28T19:45:00Z"},
        {"bucketId": "3p-weekly", "remainingFraction": 0.97, "resetTime": "2026-09-01T07:00:00Z"}
      ]}
    ]}
    """.utf8)

    @Test func parsesPooledBuckets() throws {
        let status = try GeminiProvider.parseSummary(Self.fixture)
        #expect(abs(status.ringFraction! - 0.18) < 0.0001)   // 1 - 0.82
        #expect(status.ringLabel == "18%")
        #expect(status.metrics.map(\.label) == ["Current session", "Weekly", "Other models", "Other weekly"])
        #expect(abs(status.metrics[1].fraction! - 0.36) < 0.0001)
    }

    @Test func readsNestedAndOneofFractions() throws {
        let data = Data("""
        {"response": {"groups": [{"buckets": [
          {"bucketId": "gemini-5h", "remaining": {"remainingFraction": 0.5, "resetTime": "2026-08-28T19:45:00Z"}},
          {"bucketId": "gemini-weekly", "remaining": {"case": "remainingFraction", "value": 0.75}}
        ]}]}}
        """.utf8)
        let status = try GeminiProvider.parseSummary(data)
        #expect(status.ringFraction == 0.5)
        #expect(status.metrics.count == 2)
        #expect(status.metrics[1].fraction == 0.25)
    }

    @Test func missingFractionMeansNoData() throws {
        let data = Data("""
        {"groups": [{"buckets": [
          {"bucketId": "gemini-5h", "resetTime": "2026-08-28T19:45:00Z"},
          {"bucketId": "gemini-weekly", "remainingFraction": 0.9}
        ]}]}
        """.utf8)
        let status = try GeminiProvider.parseSummary(data)
        // The fractionless session bucket is skipped, never defaulted to 0 or 1.
        #expect(status.metrics.map(\.label) == ["Weekly"])
    }
}

@Suite struct GeminiLegacyParsingTests {
    @Test func poolsWorstBucketPerModel() throws {
        let data = Data("""
        {"buckets": [
          {"modelId": "gemini-3-pro", "remainingFraction": 0.85, "tokenType": "INPUT", "resetTime": "2026-08-29T07:00:00Z"},
          {"modelId": "gemini-3-pro", "remainingFraction": 0.40, "tokenType": "REQUESTS"},
          {"modelId": "gemini-3-flash", "remainingFraction": 0.95}
        ]}
        """.utf8)
        let status = try GeminiProvider.parseLegacy(data)
        #expect(abs(status.ringFraction! - 0.6) < 0.0001)   // worst gemini-3-pro bucket
        #expect(status.ringLabel == "60%")
        #expect(status.metrics.first?.label == "gemini-3-pro")
    }

    @Test func emptyBucketsThrows() {
        #expect(throws: (any Error).self) {
            _ = try GeminiProvider.parseLegacy(Data(#"{"buckets": []}"#.utf8))
        }
    }
}

@Suite struct GeminiCredentialTests {
    @Test func parsesGoKeyringBase64() throws {
        let json = #"{"token": {"access_token": "ya29.test", "refresh_token": "1//refresh", "expiry": "2099-01-01T00:00:00Z"}}"#
        let wrapped = "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
        let creds = try #require(GeminiTokenStore.parse(keychainValue: wrapped))
        #expect(creds.accessToken == "ya29.test")
        #expect(creds.refreshToken == "1//refresh")
        #expect(creds.isFresh)
    }

    @Test func parsesRootLevelAndBareToken() throws {
        let root = try #require(GeminiTokenStore.parse(keychainValue: #"{"accessToken": "ya29.camel"}"#))
        #expect(root.accessToken == "ya29.camel")
        let bare = try #require(GeminiTokenStore.parse(keychainValue: "Bearer ya29.bare"))
        #expect(bare.accessToken == "ya29.bare")
    }

    @Test func cliCredsExpiryIsEpochMillis() throws {
        let json = Data(#"{"access_token": "ya29.cli", "refresh_token": "1//r", "expiry_date": 1756350000000}"#.utf8)
        let creds = try #require(GeminiTokenStore.parse(credsJSON: json))
        #expect(creds.expiry == Date(timeIntervalSince1970: 1_756_350_000))
        #expect(!creds.isFresh)   // that date is in the past relative to test runs
    }
}
