import XCTest
@testable import Kinetriq

final class AuthJSONDecodingTests: XCTestCase {

    func testParsesFractionalSecondsUsedByGoTrue() {
        XCTAssertNotNil(ISO8601Timestamp.parse("2026-08-27T06:46:52.624123Z"))
        XCTAssertNotNil(ISO8601Timestamp.parse("2026-08-27T06:46:52.624Z"))
        XCTAssertNotNil(ISO8601Timestamp.parse("2026-08-27T06:46:52Z"))
        XCTAssertNotNil(ISO8601Timestamp.parse("2026-08-27T06:46:52.624123+00:00"))
    }

    func testDecodesAppleSignInResponseWithMicrosecondCreatedAt() throws {
        let data = goTrueTokenJSON(createdAt: "2026-08-27T06:46:52.624123Z")
        let response = try AuthResponseParser.decode(data)
        let session = try XCTUnwrap(response.authSession)

        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.refreshToken, "refresh-token")
        XCTAssertEqual(session.user.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(session.user.email, "tester@privaterelay.appleid.com")
        XCTAssertNotNil(session.user.createdAt)
    }

    func testDecodesAppleSignInWhenEmailIsHidden() throws {
        let data = goTrueTokenJSON(createdAt: "2026-08-27T02:18:04.275000Z", email: nil)
        let session = try XCTUnwrap(try AuthResponseParser.decode(data).authSession)
        XCTAssertEqual(session.user.email, "")
        XCTAssertNotNil(session.user.createdAt)
    }

    func testBuiltInISO8601StrategyStillRejectsFractionalSeconds() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(#"{"created_at":"2026-08-27T06:46:52.624123Z"}"#.utf8)

        struct Dated: Decodable {
            let createdAt: Date
            enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
        }

        XCTAssertThrowsError(try decoder.decode(Dated.self, from: data))
    }

    func testSignUpWithoutSessionStillDecodes() throws {
        let json = """
        {
          "access_token": null,
          "user": {
            "id": "11111111-1111-1111-1111-111111111111",
            "email": "new@example.com",
            "created_at": "2026-08-27T06:46:52.624123Z"
          }
        }
        """
        let response = try AuthResponseParser.decode(Data(json.utf8))
        XCTAssertNil(response.authSession)
        XCTAssertEqual(response.user?.id, "11111111-1111-1111-1111-111111111111")
    }

    @MainActor
    func testDecodingFailureMapsToFriendlyCode() {
        let message = AuthService.userFacingMessage(for: DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "bad date")
        ))
        XCTAssertTrue(message.contains("AUTH-DECODE"), message)
        XCTAssertFalse(message.contains("NSCocoaErrorDomain"), message)
    }

    private func goTrueTokenJSON(createdAt: String, email: String? = "tester@privaterelay.appleid.com") -> Data {
        let emailJSON = email.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "access_token": "access-token",
          "token_type": "bearer",
          "expires_in": 3600,
          "expires_at": 1756272412,
          "refresh_token": "refresh-token",
          "user": {
            "id": "11111111-1111-1111-1111-111111111111",
            "aud": "authenticated",
            "role": "authenticated",
            "email": \(emailJSON),
            "email_confirmed_at": "\(createdAt)",
            "app_metadata": { "provider": "apple", "providers": ["apple"] },
            "user_metadata": { "iss": "https://appleid.apple.com", "email_verified": true },
            "created_at": "\(createdAt)",
            "updated_at": "\(createdAt)",
            "is_anonymous": false
          }
        }
        """
        return Data(json.utf8)
    }
}
