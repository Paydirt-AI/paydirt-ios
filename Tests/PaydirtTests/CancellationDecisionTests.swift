import XCTest
@testable import Paydirt

/// Serves canned responses for `URLSession.shared` and records the last request.
private final class DecideURLProtocol: URLProtocol {
    static var statusCode = 200
    static var responseBody = Data()
    static var lastRequest: URLRequest?
    static var lastBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "paydirt.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = Self.readBody(request).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class CancellationDecisionTests: XCTestCase {
    private let detectedAt = Date(timeIntervalSince1970: 1_790_000_000)
    private let expiration = Date(timeIntervalSince1970: 1_790_600_000)

    private func request(userId: String? = "user-1") -> CancellationDecisionRequest {
        CancellationDecisionRequest(
            dedupKey: "revenuecat_pro_123",
            isTrial: true,
            productId: "pro.monthly",
            periodType: "Trial",
            provider: "revenuecat",
            userId: userId,
            entitlementId: "pro",
            detectedAt: detectedAt,
            expirationDate: expiration,
            preferredFormId: "trial-form"
        )
    }

    override func setUp() {
        super.setUp()
        DecideURLProtocol.statusCode = 200
        DecideURLProtocol.responseBody = Data()
        DecideURLProtocol.lastRequest = nil
        DecideURLProtocol.lastBody = nil
        URLProtocol.registerClass(DecideURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(DecideURLProtocol.self)
        super.tearDown()
    }

    // MARK: Request body

    func testRequestBodyUsesContractFieldNamesAndISODates() {
        let body = request().jsonObject
        XCTAssertEqual(body["dedup_key"] as? String, "revenuecat_pro_123")
        XCTAssertEqual(body["is_trial"] as? Bool, true)
        XCTAssertEqual(body["product_id"] as? String, "pro.monthly")
        XCTAssertEqual(body["period_type"] as? String, "Trial")
        XCTAssertEqual(body["provider"] as? String, "revenuecat")
        XCTAssertEqual(body["user_id"] as? String, "user-1")
        XCTAssertEqual(body["entitlement_id"] as? String, "pro")
        XCTAssertEqual(body["preferred_form_id"] as? String, "trial-form")
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(body["detected_at"] as? String, iso.string(from: detectedAt))
        XCTAssertEqual(body["expiration_date"] as? String, iso.string(from: expiration))
    }

    func testRequestBodyOmitsNilFields() {
        let body = CancellationDecisionRequest(
            dedupKey: "key", isTrial: false, productId: "p", periodType: "Normal", provider: "storekit",
            userId: nil, entitlementId: nil, detectedAt: nil, expirationDate: nil, preferredFormId: nil
        ).jsonObject
        XCTAssertEqual(Set(body.keys), ["dedup_key", "is_trial", "product_id", "period_type", "provider"])
    }

    // MARK: Response parsing

    func testDecodesShowDecision() throws {
        let json = #"{"show":true,"reason":"eligible","form_id":"form-1","decision_id":"d-1"}"#
        let decision = try JSONDecoder().decode(CancellationDecision.self, from: Data(json.utf8))
        XCTAssertEqual(decision, CancellationDecision(show: true, reason: "eligible", formId: "form-1", decisionId: "d-1"))
    }

    func testDecodesSkipDecisionWithNullFormId() throws {
        let json = #"{"show":false,"reason":"stale","form_id":null,"decision_id":"d-2"}"#
        let decision = try JSONDecoder().decode(CancellationDecision.self, from: Data(json.utf8))
        XCTAssertFalse(decision.show)
        XCTAssertEqual(decision.reason, "stale")
        XCTAssertNil(decision.formId)
    }

    // MARK: Routing / fallback

    private func route(_ show: Bool, _ reason: String, _ formId: String? = nil) -> Paydirt.CancellationPromptRoute {
        Paydirt.cancellationPromptRoute(for: .success(.decided(
            CancellationDecision(show: show, reason: reason, formId: formId, decisionId: "d")
        )))
    }

    func testShowPresentsServerFormIdWithDecisionId() {
        XCTAssertEqual(route(true, "eligible", "form-1"), .present(formId: "form-1", decisionId: "d"))
    }

    // MARK: Response metadata

    func testSubscriptionMetadataCarriesDecisionIdOnlyWhenDecided() {
        let cancellation = PaydirtSubscriptionCancellation(provider: .revenueCat, productId: "pro.monthly", isTrial: false)
        let decided = Paydirt.shared.subscriptionMetadata(for: cancellation, decisionId: "d-1")
        XCTAssertEqual((decided["subscription"] as? [String: Any])?["paydirt_decision_id"] as? String, "d-1")
        let legacy = Paydirt.shared.subscriptionMetadata(for: cancellation)
        XCTAssertNil((legacy["subscription"] as? [String: Any])?["paydirt_decision_id"])
    }

    func testShowWithoutFormIdFailsClosed() {
        XCTAssertEqual(route(true, "eligible", nil), .skip(reason: "missing_form_id", rememberLocally: false))
    }

    func testFinalSkipReasonsAreRememberedLocally() {
        for reason in ["already_asked", "promotional", "stale"] {
            XCTAssertEqual(route(false, reason), .skip(reason: reason, rememberLocally: true), reason)
        }
    }

    func testNoFormAndUnknownSkipReasonsAreNotRemembered() {
        XCTAssertEqual(route(false, "no_form"), .skip(reason: "no_form", rememberLocally: false))
        XCTAssertEqual(route(false, "future_reason"), .skip(reason: "future_reason", rememberLocally: false))
    }

    func testOlderServerFallsBackToLegacyLookup() {
        XCTAssertEqual(Paydirt.cancellationPromptRoute(for: .success(.unsupported)), .legacyLookup)
    }

    func testNetworkErrorFailsClosed() {
        let route = Paydirt.cancellationPromptRoute(for: .failure(URLError(.notConnectedToInternet)))
        XCTAssertEqual(route, .skip(reason: "decision_unavailable", rememberLocally: false))
    }

    // MARK: API client

    func testClientPostsAuthenticatedDecisionAndParsesResponse() async throws {
        DecideURLProtocol.responseBody = Data(#"{"show":true,"reason":"eligible","form_id":"form-1","decision_id":"d-1"}"#.utf8)
        let client = PaydirtAPIClient(apiKey: "pk_test_key", baseURL: "https://paydirt.test")
        let outcome = try await client.decideCancellation(request())
        XCTAssertEqual(outcome, .decided(CancellationDecision(show: true, reason: "eligible", formId: "form-1", decisionId: "d-1")))
        let sent = try XCTUnwrap(DecideURLProtocol.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.path, "/api/cancellations/decide")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "pk_test_key")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-paydirt-sdk-version"), "2.3.0")
        XCTAssertEqual(DecideURLProtocol.lastBody?["dedup_key"] as? String, "revenuecat_pro_123")
    }

    func testClientTreats404AsOlderServer() async throws {
        DecideURLProtocol.statusCode = 404
        DecideURLProtocol.responseBody = Data(#"{"error":"Not found"}"#.utf8)
        let client = PaydirtAPIClient(apiKey: "pk_test_key", baseURL: "https://paydirt.test")
        let outcome = try await client.decideCancellation(request())
        XCTAssertEqual(outcome, .unsupported)
    }

    func testClientReportsPresentationForDecision() async throws {
        DecideURLProtocol.responseBody = Data(#"{"ok":true}"#.utf8)
        let client = PaydirtAPIClient(apiKey: "pk_test_key", baseURL: "https://paydirt.test")
        try await client.markCancellationDecisionPresented(decisionId: "55555555-5555-4555-8555-555555555555")
        let sent = try XCTUnwrap(DecideURLProtocol.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.path, "/api/cancellations/decisions/55555555-5555-4555-8555-555555555555/presented")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "pk_test_key")
    }

    func testClientPresentationReportThrowsOnUnknownDecision() async {
        DecideURLProtocol.statusCode = 404
        let client = PaydirtAPIClient(apiKey: "pk_test_key", baseURL: "https://paydirt.test")
        do {
            try await client.markCancellationDecisionPresented(decisionId: "unknown")
            XCTFail("Expected an error")
        } catch {}
    }

    func testClientThrowsOnServerError() async {
        DecideURLProtocol.statusCode = 500
        let client = PaydirtAPIClient(apiKey: "pk_test_key", baseURL: "https://paydirt.test")
        do {
            _ = try await client.decideCancellation(request())
            XCTFail("Expected an error")
        } catch {}
    }
}
