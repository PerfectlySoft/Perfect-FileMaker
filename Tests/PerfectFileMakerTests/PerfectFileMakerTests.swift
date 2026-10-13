import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PerfectFileMaker

// MARK: - Live-server test configuration
//
// Gated behind FILEMAKER_TESTS=1, matching this monorepo's established
// <X>_TESTS=1 convention (Perfect-Redis, Perfect-Session, etc.) — these
// hit a real FileMaker Server's "FMServer_Sample" sample database, which
// this modernization pass has no live instance to verify against. They're
// preserved (converted to async/await + swift-testing) rather than
// deleted so a deployment with real server access can still run them.

private func liveTestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["FILEMAKER_TESTS"] == "1"
}

private let testHost = ProcessInfo.processInfo.environment["FILEMAKER_HOST"] ?? "127.0.0.1"
private let testPort = Int(ProcessInfo.processInfo.environment["FILEMAKER_PORT"] ?? "") ?? 80
private let testUserName = ProcessInfo.processInfo.environment["FILEMAKER_USER"] ?? ""
private let testPassword = ProcessInfo.processInfo.environment["FILEMAKER_PASSWORD"] ?? ""
private let sampleDB = "FMServer_Sample"
private let sampleLayout = "Task Details"

private func liveServer() -> FileMakerServer {
    FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
}

// MARK: - Query string building (pure, no network)
//
// Literal expected strings reflect this modernization's stricter
// `String.fmpEscaped` encoder (alnum + `-._~` only) — deliberately
// narrower than the original `PerfectLib.stringByEncodingURL`, which left
// `= * & ! ( ) ; ' , / ? @` unescaped. `(`/`)` (in `-query=(q1)`) and `@` (in a
// literal task name below) now percent-encode to `%28`/`%29`/`%40` where
// the old fixtures showed them literal — see FMPQuery.swift's doc
// comments for why over-encoding here is safe, not a regression.

@Test func querySkipMaxBuildsExpectedString() {
    let query = FMPQuery(database: sampleDB, layout: sampleLayout, action: .findAll).maxRecords(0)
    #expect("\(query)" == "-db=FMServer_Sample&-lay=Task%20Details&-skip=0&-max=0&-findall")

    let query2 = FMPQuery(database: sampleDB, layout: sampleLayout, action: .findAll).skipRecords(2).maxRecords(2)
    #expect("\(query2)" == "-db=FMServer_Sample&-lay=Task%20Details&-skip=2&-max=2&-findall")
}

@Test func queryFindInProgressBuildsExpectedString() {
    let qfields = [FMPQueryFieldGroup(fields: [FMPQueryField(name: "Status", value: "In Progress")])]
    let query = FMPQuery(database: sampleDB, layout: sampleLayout, action: .find).queryFields(qfields)
    #expect("\(query)" == "-db=FMServer_Sample&-lay=Task%20Details&-skip=0&-max=all&-query=%28q1%29&-q1=Status&-q1.value===In%20Progress*&-findquery")
}

@Test func queryNewBuildsExpectedStringWithNonAsciiAndReservedCharactersEscaped() {
    let task = "Add a new record @ 123 \u{2603}\u{FE0F}"
    let qfields = [FMPQueryField(name: "Task", value: task), FMPQueryField(name: "Status", value: "In Progress")]
    let query = FMPQuery(database: sampleDB, layout: sampleLayout, action: .new).queryFields(qfields)
    #expect("\(query)" == "-db=FMServer_Sample&-lay=Task%20Details&Task=Add%20a%20new%20record%20%40%20123%20%E2%98%83%EF%B8%8F&Status=In%20Progress&-new")
}

// MARK: - Operator encoding
//
// `valueWithOp` keeps the operator token literal and encodes only the
// value. (3.0.1 encoded operator and value together with PerfectLib's
// encoder, which encoded `<`/`>` and left `=`/`*` literal; after the
// server form-decodes the body that is equivalent, so the old operators
// worked. What it got wrong was leaving `&` in values literal.) These pin
// the query string for every operator.

@Test func comparisonOperatorsAreSentLiterallyWithEncodedValues() {
    let cases: [(FMPFieldOp, String, String)] = [
        (.equal, "5", "==5"),
        (.contains, "abc", "==*abc*"),
        (.beginsWith, "abc", "==abc*"),
        (.endsWith, "abc", "==*abc"),
        (.greaterThan, "5", ">5"),
        (.greaterThanEqual, "5", ">=5"),
        (.lessThan, "5", "<5"),
        (.lessThanEqual, "5", "<=5"),
    ]
    for (op, value, expected) in cases {
        let field = FMPQueryField(name: "Count", value: value, op: op)
        #expect(field.valueWithOp == expected, "op \(op)")

        let query = FMPQuery(database: "DB", layout: "Layout", action: .find)
            .queryFields([FMPQueryFieldGroup(fields: [field])])
        // The operator's own characters (< > = *) must survive as
        // literal, unencoded query syntax — not %3C/%3E/%3D/%2A.
        #expect("\(query)".contains("-q1.value=\(expected)"), "op \(op): \(query)")
    }
}

@Test func comparisonValueContainingReservedCharactersIsEscapedButOperatorIsNot() {
    // A value containing '&' must not be able to smuggle an extra query
    // directive — this is the actual vulnerability the stricter encoder
    // closes (see FMPQuery.swift's String.fmpEscaped doc comment).
    let field = FMPQueryField(name: "Name", value: "a&-findquery", op: .greaterThan)
    #expect(field.valueWithOp == ">a%26-findquery")
}

// MARK: - URLProtocol mock (captures the outgoing request, returns a canned response)

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest, Data?) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.lastBody = body
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request, body)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession converts `httpBody` to a stream, so read the stream when needed.
    static func bodyData(from request: URLRequest) -> Data? {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A plain local `var` can't be mutated from inside a `@Sendable` mock
/// handler closure — this box gives the handler somewhere thread-safe
/// (for this single-threaded mock's purposes) to stash a captured value.
private final class CapturedValueBox: @unchecked Sendable {
    var value: String?
}

private func mockServer(handler: @escaping @Sendable (URLRequest, Data?) -> (HTTPURLResponse, Data)) -> FileMakerServer {
    MockURLProtocol.lastBody = nil
    MockURLProtocol.requestHandler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return FileMakerServer(host: "mock.example", port: 443, userName: "u", password: "p", urlSession: session)
}

private func okResponse(_ body: String) -> @Sendable (URLRequest, Data?) -> (HTTPURLResponse, Data) {
    { req, _ in
        let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (http, Data(body.utf8))
    }
}

private let sampleResultSetXML = """
<?xml version="1.0" encoding="UTF-8"?>
<fmresultset xmlns="http://www.filemaker.com/xml/fmresultset" version="1.0">
<error code="0"/>
<product build="1" name="FileMaker" version="1"/>
<datasource database="TestDB" date-format="MM/dd/yyyy" layout="TestLayout" table="TestTable" time-format="HH:mm:ss" timestamp-format="MM/dd/yyyy HH:mm:ss" total-count="1"/>
<metadata>
<field-definition name="Status" result="text" type="normal"/>
</metadata>
<resultset count="1" fetch-size="1">
<record record-id="42" mod-id="0">
<field name="Status"><data>In Progress</data></field>
</record>
</resultset>
</fmresultset>
"""

/// A `-view`/find response shaped like FileMaker Server's: `result=` carries
/// the field's data type (`type=` is normal/calculation/summary), and a
/// portal appears as a `relatedset-definition` plus `relatedset` rows.
private let layoutResultSetXML = """
<?xml version="1.0" encoding="UTF-8"?>
<fmresultset xmlns="http://www.filemaker.com/xml/fmresultset" version="1.0">
<error code="0"/>
<product build="1" name="FileMaker Web Publishing Engine" version="1"/>
<datasource database="TestDB" date-format="MM/dd/yyyy" layout="Task Details" table="Tasks" time-format="HH:mm:ss" timestamp-format="MM/dd/yyyy HH:mm:ss" total-count="1"/>
<metadata>
<field-definition auto-enter="no" global="no" max-repeat="1" name="Count" not-empty="no" numeric-only="no" result="number" time-of-day="no" type="normal"/>
<field-definition auto-enter="no" global="no" max-repeat="1" name="Due" not-empty="no" numeric-only="no" result="date" time-of-day="no" type="normal"/>
<field-definition auto-enter="no" global="no" max-repeat="1" name="Status" not-empty="no" numeric-only="no" result="text" time-of-day="no" type="calculation"/>
<relatedset-definition table="Items">
<field-definition auto-enter="no" global="no" max-repeat="1" name="Items::Name" not-empty="no" numeric-only="no" result="text" time-of-day="no" type="normal"/>
<field-definition auto-enter="no" global="no" max-repeat="1" name="Items::Qty" not-empty="no" numeric-only="no" result="number" time-of-day="no" type="normal"/>
</relatedset-definition>
</metadata>
<resultset count="1" fetch-size="1">
<record mod-id="3" record-id="7">
<field name="Count"><data>12</data></field>
<field name="Due"><data>10/06/2026</data></field>
<field name="Status"><data>Open</data></field>
<relatedset count="2" table="Items">
<record mod-id="0" record-id="100"><field name="Items::Name"><data>Bolt</data></field><field name="Items::Qty"><data>4</data></field></record>
<record mod-id="0" record-id="101"><field name="Items::Name"><data>Nut</data></field><field name="Items::Qty"><data>9</data></field></record>
</relatedset>
</record>
</resultset>
</fmresultset>
"""

@Suite(.serialized)
struct MockedFileMakerServerTests {
    @Test func queryParsesSuccessfulResultSet() async throws {
        let server = mockServer(handler: okResponse(sampleResultSetXML))
        let query = FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll)
        let resultSet = try await server.query(query)
        #expect(resultSet.records.count == 1)
        #expect(resultSet.databaseInfo.recordCount == 1)
        guard case .field(let name, let value) = resultSet.records.first?.elements["Status"] else {
            Issue.record("Expected a .field item")
            return
        }
        #expect(name == "Status")
        #expect("\(value)" == "In Progress")
    }

    @Test func queryThrowsServerErrorForNonZeroErrorCode() async {
        let errorXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fmresultset xmlns="http://www.filemaker.com/xml/fmresultset" version="1.0">
        <error code="105"/>
        </fmresultset>
        """
        let server = mockServer(handler: okResponse(errorXML))
        let query = FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll)
        await #expect(throws: FMPError.self) {
            _ = try await server.query(query)
        }
    }

    @Test func queryThrowsServerErrorForNon200HTTPStatus() async {
        let server = mockServer { req, _ in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        let query = FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll)
        await #expect(throws: FMPError.self) {
            _ = try await server.query(query)
        }
    }

    @Test func databaseNamesParsesFieldNamedDatabaseName() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fmresultset xmlns="http://www.filemaker.com/xml/fmresultset" version="1.0">
        <error code="0"/>
        <datasource database="DBNames" date-format="MM/dd/yyyy" layout="" table="" time-format="HH:mm:ss" timestamp-format="MM/dd/yyyy HH:mm:ss" total-count="1"/>
        <metadata><field-definition name="DATABASE_NAME" result="text" type="normal"/></metadata>
        <resultset count="1" fetch-size="1">
        <record record-id="1" mod-id="0"><field name="DATABASE_NAME"><data>\(sampleDB)</data></field></record>
        </resultset>
        </fmresultset>
        """
        let server = mockServer(handler: okResponse(xml))
        let names = try await server.databaseNames()
        #expect(names == [sampleDB])
    }

    @Test func layoutNamesParsesLayoutNameFieldsAndSendsLayoutnames() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fmresultset xmlns="http://www.filemaker.com/xml/fmresultset" version="1.0">
        <error code="0"/>
        <datasource database="TestDB" date-format="MM/dd/yyyy" layout="" table="" time-format="HH:mm:ss" timestamp-format="MM/dd/yyyy HH:mm:ss" total-count="2"/>
        <metadata><field-definition name="LAYOUT_NAME" result="text" type="normal"/></metadata>
        <resultset count="2" fetch-size="2">
        <record record-id="1" mod-id="0"><field name="LAYOUT_NAME"><data>Task Details</data></field></record>
        <record record-id="2" mod-id="0"><field name="LAYOUT_NAME"><data>Tasks &amp; Notes</data></field></record>
        </resultset>
        </fmresultset>
        """
        let server = mockServer(handler: okResponse(xml))
        let names = try await server.layoutNames(database: "Test DB")
        #expect(names == ["Task Details", "Tasks & Notes"])
        let body = String(data: MockURLProtocol.lastBody ?? Data(), encoding: .utf8)
        #expect(body == "-db=Test%20DB&-layoutnames")
    }

    @Test func layoutInfoReadsResultTypesAndPortalDefinitions() async throws {
        let server = mockServer(handler: okResponse(layoutResultSetXML))
        let info = try await server.layoutInfo(database: "TestDB", layout: "Task Details")
        let body = String(data: MockURLProtocol.lastBody ?? Data(), encoding: .utf8)
        #expect(body == "-db=TestDB&-lay=Task%20Details&-view")

        #expect(info.fields.count == 4)
        guard case .fieldDefinition(let count) = info.fields[0] else {
            Issue.record("Expected a field definition first")
            return
        }
        #expect(count.name == "Count")
        #expect(count.type == .number)
        guard case .relatedSetDefinition(let table, let portalFields) = info.fields[3] else {
            Issue.record("Expected a related-set definition last")
            return
        }
        #expect(table == "Items")
        #expect(portalFields.map(\.name) == ["Items::Name", "Items::Qty"])
        #expect(portalFields.map(\.type) == [.text, .number])

        #expect(info.fieldsByName["Count"] == .number)
        #expect(info.fieldsByName["Due"] == .date)
        #expect(info.fieldsByName["Status"] == .text)
        #expect(info.fieldsByName["Items::Qty"] == .number)
    }

    @Test func queryTypesFieldValuesAndReadsPortalRecords() async throws {
        let server = mockServer(handler: okResponse(layoutResultSetXML))
        let resultSet = try await server.query(FMPQuery(database: "TestDB", layout: "Task Details", action: .findAll))
        #expect(resultSet.foundCount == 1)
        let record = try #require(resultSet.records.first)
        #expect(record.recordId == 7)

        guard case .field(_, .number(let count)) = record.elements["Count"] else {
            Issue.record("Count should be a number: \(String(describing: record.elements["Count"]))")
            return
        }
        #expect(count == 12)
        guard case .field(_, .date(let due)) = record.elements["Due"] else {
            Issue.record("Due should be a date")
            return
        }
        #expect(due == "10/06/2026")

        guard case .relatedSet(let table, let portalRecords) = record.elements["Items"] else {
            Issue.record("Expected the Items portal")
            return
        }
        #expect(table == "Items")
        #expect(portalRecords.map(\.recordId) == [100, 101])
        guard case .field(_, .text(let name)) = portalRecords[0].elements["Items::Name"],
              case .field(_, .number(let qty)) = portalRecords[0].elements["Items::Qty"] else {
            Issue.record("Unexpected portal row: \(portalRecords[0].elements)")
            return
        }
        #expect(name == "Bolt")
        #expect(qty == 4)
    }

    @Test func noRecordsMatchError401Throws() async {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fmresultset xmlns="http://www.filemaker.com/xml/fmresultset" version="1.0">
        <error code="401"/>
        <product build="1" name="FileMaker Web Publishing Engine" version="1"/>
        <datasource database="TestDB" date-format="MM/dd/yyyy" layout="Task Details" table="Tasks" time-format="HH:mm:ss" timestamp-format="MM/dd/yyyy HH:mm:ss" total-count="3"/>
        <metadata><field-definition name="Status" result="text" type="normal"/></metadata>
        <resultset count="0" fetch-size="0"/>
        </fmresultset>
        """
        let server = mockServer(handler: okResponse(xml))
        let query = FMPQuery(database: "TestDB", layout: "Task Details", action: .find)
            .queryFields([FMPQueryFieldGroup(fields: [FMPQueryField(name: "Status", value: "Nothing")])])
        do {
            _ = try await server.query(query)
            Issue.record("Expected FMPError.serverError(401, ...)")
        } catch FMPError.serverError(let code, _) {
            #expect(code == 401)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func requestSendsBasicAuthHeaderWhenCredentialsProvided() async throws {
        let captured = CapturedValueBox()
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = { req, _ in
            captured.value = req.value(forHTTPHeaderField: "Authorization")
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(sampleResultSetXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let server = FileMakerServer(host: "mock.example", port: 443, userName: "user", password: "pass", urlSession: session)
        _ = try await server.query(FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll))

        let expectedAuth = "Basic " + Data("user:pass".utf8).base64EncodedString()
        #expect(captured.value == expectedAuth)
    }

    @Test func requestOmitsAuthHeaderWhenNoUsername() async throws {
        let captured = CapturedValueBox()
        captured.value = "unset"
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = { req, _ in
            captured.value = req.value(forHTTPHeaderField: "Authorization")
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(sampleResultSetXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let server = FileMakerServer(host: "mock.example", port: 443, userName: "", password: "", urlSession: session)
        _ = try await server.query(FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll))

        #expect(captured.value == nil)
    }

    @Test func requestSendsConnectionCloseToAvoidLeakingWebPublishingSessions() async throws {
        // Classic XML Web Publishing has no login/logout call, so the
        // underlying HTTP connection is the only session-lifecycle signal
        // a client can give — without this header, URLSession's default
        // keep-alive leaves connections (and the Web Publishing Engine
        // sessions tracked against them) open indefinitely. Real-world
        // symptom: FileMaker Server's admin console showing dozens of
        // still-"open" client connections from a server that made one
        // request per connection, spread out over many minutes.
        let captured = CapturedValueBox()
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = { req, _ in
            captured.value = req.value(forHTTPHeaderField: "Connection")
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(sampleResultSetXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let server = FileMakerServer(host: "mock.example", port: 443, userName: "user", password: "pass", urlSession: session)
        _ = try await server.query(FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll))

        #expect(captured.value == "close")
    }

    @Test func requestSendsQueryAsPOSTBodyNotURLQueryString() async throws {
        // XML Custom Web Publishing over plain HTTP puts search/field
        // values (which can include credential-adjacent data — a
        // password-derived lookup value on a login page, for example)
        // into the query. A GET-with-URL-query request (briefly tried
        // 2026-07-17, then reverted) puts that same data somewhere every
        // web server, proxy, and this library's own plain-HTTP warning
        // log line records verbatim — a real regression, confirmed live:
        // this exact warning line went from logging just the bare
        // endpoint URL to logging the entire query, credentials-adjacent
        // values included. POST keeps the query out of any URL-based
        // logging. (Separately: GET was originally suspected of fixing a
        // FileMaker Server connectivity outage this same query string
        // caused; further live testing showed the outage was unrelated
        // to GET vs. POST — POST works reliably once the server itself
        // is healthy — so there was no connectivity reason to keep GET
        // once the security cost was found.)
        let captured = CapturedValueBox()
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = { req, body in
            captured.value = req.httpMethod
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(sampleResultSetXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let server = FileMakerServer(host: "mock.example", port: 443, userName: "user", password: "pass", urlSession: session)
        _ = try await server.query(FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll))

        #expect(captured.value == "POST")
        #expect(MockURLProtocol.lastBody?.isEmpty == false)
        let bodyString = String(data: MockURLProtocol.lastBody ?? Data(), encoding: .utf8)
        #expect(bodyString?.contains("-db=TestDB") == true)
        #expect(bodyString?.contains("-lay=TestLayout") == true)
        #expect(bodyString?.contains("-findall") == true)
    }

    @Test func requestDefaultsToAFiveSecondTimeoutNotURLSessionsSixty() async throws {
        // Earlier versions set no timeout of their own: 3.0.1 (Perfect-CURL)
        // set none, and pre-release URLSession builds used URLSession's
        // 60-second default.
        // Live-confirmed (2026-07-17) as a real contributor to FileMaker
        // Server Web Publishing Engine session buildup under crawl-style
        // load: a calling application reasonably gives up on a slow
        // response well before 60 seconds, but this library's own request
        // kept running in the background regardless, holding its WPE
        // session open the whole time.
        final class TimeoutBox: @unchecked Sendable {
            var value: TimeInterval?
        }
        let captured = TimeoutBox()
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = { req, _ in
            captured.value = req.timeoutInterval
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(sampleResultSetXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let server = FileMakerServer(host: "mock.example", port: 443, userName: "user", password: "pass", urlSession: session)
        _ = try await server.query(FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll))

        #expect(captured.value == 5)
    }

    @Test func requestHonorsAnExplicitDefaultTimeoutOverride() async throws {
        // A large-dataset query or one that triggers a FileMaker script
        // legitimately needs longer than the 5-second default — a
        // consumer that knows this ahead of time constructs its
        // `FileMakerServer` with a longer `defaultTimeout` for that
        // specific connection.
        final class TimeoutBox: @unchecked Sendable {
            var value: TimeInterval?
        }
        let captured = TimeoutBox()
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = { req, _ in
            captured.value = req.timeoutInterval
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(sampleResultSetXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let server = FileMakerServer(host: "mock.example", port: 443, userName: "user", password: "pass", urlSession: session, defaultTimeout: 30)
        _ = try await server.query(FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll))

        #expect(captured.value == 30)
    }

    @Test func requestURLNeverContainsTheQuery() async throws {
        // The plain-HTTP credential warning below logs `url.absoluteString`
        // verbatim — this test guards against a query string ever ending
        // up in the URL (and therefore in that log line, or any other
        // URL-based logging FileMaker Server's own web layer does).
        let captured = CapturedValueBox()
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = { req, _ in
            captured.value = req.url?.query
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(sampleResultSetXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let server = FileMakerServer(host: "mock.example", port: 443, userName: "user", password: "pass", urlSession: session)
        _ = try await server.query(FMPQuery(database: "TestDB", layout: "TestLayout", action: .findAll))

        #expect(captured.value == nil)
    }
}

// MARK: - Live FileMaker Server integration tests (FILEMAKER_TESTS=1)

@Test(.enabled(if: liveTestsEnabled(), "Set FILEMAKER_TESTS=1 to run against a FileMaker Server"))
func liveDatabaseNamesIncludesSampleDatabase() async throws {
    let names = try await liveServer().databaseNames()
    #expect(names.contains(sampleDB))
}

@Test(.enabled(if: liveTestsEnabled(), "Set FILEMAKER_TESTS=1 to run against a FileMaker Server"))
func liveLayoutNamesIncludesSampleLayout() async throws {
    let names = try await liveServer().layoutNames(database: sampleDB)
    #expect(names.contains(sampleLayout))
}

@Test(.enabled(if: liveTestsEnabled(), "Set FILEMAKER_TESTS=1 to run against a FileMaker Server"))
func liveLayoutInfoIncludesExpectedFields() async throws {
    let expectedNames = ["Status", "Category", "Description", "Task", "Related | Sort Selection",
                          "Days Till Due", "Due Date", "Assignees::Name", "Assignees::Phone",
                          "Assignees::Email", "Attachments::Attachment | Container",
                          "Attachments::Comments", "Related Tasks::Task",
                          "Related Tasks::Due Date", "Related Tasks::Description"]
    let layoutInfo = try await liveServer().layoutInfo(database: sampleDB, layout: sampleLayout)
    let fieldsByName = layoutInfo.fieldsByName
    for expectedField in expectedNames {
        #expect(fieldsByName[expectedField] != nil, "missing \(expectedField)")
    }
}

@Test(.enabled(if: liveTestsEnabled(), "Set FILEMAKER_TESTS=1 to run against a FileMaker Server"))
func liveQuerySkipMaxReturnsExpectedRecordCounts() async throws {
    let fms = liveServer()

    let zeroQuery = FMPQuery(database: sampleDB, layout: sampleLayout, action: .findAll).maxRecords(0)
    let zeroResult = try await fms.query(zeroQuery)
    #expect(zeroResult.records.count == 0)

    let twoQuery = FMPQuery(database: sampleDB, layout: sampleLayout, action: .findAll).skipRecords(2).maxRecords(2)
    let twoResult = try await fms.query(twoQuery)
    #expect(twoResult.records.count == 2)
}

@Test(.enabled(if: liveTestsEnabled(), "Set FILEMAKER_TESTS=1 to run against a FileMaker Server"))
func liveQueryFindAllReturnsRecordsMatchingLayout() async throws {
    let fms = liveServer()
    let query = FMPQuery(database: sampleDB, layout: sampleLayout, action: .findAll)
    let resultSet = try await fms.query(query)
    let fields = resultSet.layoutInfo.fields
    #expect(resultSet.records.count > 0)
    for rec in resultSet.records {
        for field in fields {
            switch field {
            case .fieldDefinition(let def):
                let fnd = rec.elements[def.name]
                #expect(fnd != nil, "\(def.name) not found in \(rec.elements)")
                guard case .field(let fn, _) = fnd else {
                    Issue.record("expected field \(String(describing: fnd))")
                    continue
                }
                #expect(fn == def.name)
            case .relatedSetDefinition(let name, let defs):
                let fnd = rec.elements[name]
                #expect(fnd != nil, "\(name) not found in \(rec.elements)")
                guard case .relatedSet(let fn, let relatedRecs) = fnd else {
                    Issue.record("expected relatedSet \(String(describing: fnd))")
                    continue
                }
                #expect(fn == name)
                let defNames = defs.map { $0.name }
                for relatedRec in relatedRecs {
                    for relatedRow in relatedRec.elements.values {
                        guard case .field(let fn, _) = relatedRow else {
                            Issue.record("expected field")
                            continue
                        }
                        #expect(defNames.contains(fn), "strange field name \(fn)")
                    }
                }
            }
        }
    }
}

@Test(.enabled(if: liveTestsEnabled(), "Set FILEMAKER_TESTS=1 to run against a FileMaker Server"))
func liveQueryFindInProgressReturnsMatchingStatus() async throws {
    let qfields = [FMPQueryFieldGroup(fields: [FMPQueryField(name: "Status", value: "In Progress")])]
    let query = FMPQuery(database: sampleDB, layout: sampleLayout, action: .find).queryFields(qfields)
    let resultSet = try await liveServer().query(query)
    #expect(resultSet.records.count > 0)
    for rec in resultSet.records {
        guard case .field(_, let fieldValue) = rec.elements["Status"] else { continue }
        guard case .text(let statusText) = fieldValue else {
            Issue.record("bad value \(fieldValue)")
            continue
        }
        #expect(statusText == "In Progress")
    }
}

@Test(.enabled(if: liveTestsEnabled(), "Set FILEMAKER_TESTS=1 to run against a FileMaker Server"))
func liveNewFindAndDeleteRoundTrip() async throws {
    let fms = liveServer()
    let unique = Int(Date().timeIntervalSince1970)
    let task = "Add a new record @ \(unique) \u{2603}\u{FE0F}"

    let newQuery = FMPQuery(database: sampleDB, layout: sampleLayout, action: .new)
        .queryFields([FMPQueryField(name: "Task", value: task), FMPQueryField(name: "Status", value: "In Progress")])
    _ = try await fms.query(newQuery)

    let findQuery = FMPQuery(database: sampleDB, layout: sampleLayout, action: .find)
        .queryFields([FMPQueryField(name: "Task", value: task, op: .equal)])
    let found = try await fms.query(findQuery)
    #expect(found.records.count == 1)
    let recId = try #require(found.records.first).recordId
    #expect(recId != fmpNoRecordId)

    let deleteQuery = FMPQuery(database: sampleDB, layout: sampleLayout, action: .delete).recordId(recId)
    let deleted = try await fms.query(deleteQuery)
    #expect(deleted.records.count == 0)

    let refound = try await fms.query(findQuery)
    #expect(refound.records.count == 0)
}
