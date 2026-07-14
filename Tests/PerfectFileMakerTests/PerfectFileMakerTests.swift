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
// `& = ! ( ) * ; @` unescaped. `(`/`)` (in `-query=(q1)`) and `@` (in a
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

// MARK: - Operator encoding (regression for the valueWithOp bug)
//
// Under the original PerfectLib encoder, `<`/`>` (used by
// .greaterThan/.lessThan/.greaterThanEqual/.lessThanEqual) WERE escaped,
// but only .equal/.beginsWith had test coverage — these operators were
// silently broken. Confirms the fixed `valueWithOp` (operator token
// unencoded, value encoded standalone) now produces well-formed,
// unmangled query strings for every operator.

@Test func comparisonOperatorsProduceUnmangledQueryStrings() {
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
<field-definition name="Status" type="text"/>
</metadata>
<resultset count="1" fetch-size="1">
<record record-id="42" mod-id="0">
<field name="Status"><data>In Progress</data></field>
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
        <metadata><field-definition name="DATABASE_NAME" type="text"/></metadata>
        <resultset count="1" fetch-size="1">
        <record record-id="1" mod-id="0"><field name="DATABASE_NAME"><data>\(sampleDB)</data></field></record>
        </resultset>
        </fmresultset>
        """
        let server = mockServer(handler: okResponse(xml))
        let names = try await server.databaseNames()
        #expect(names == [sampleDB])
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
}

// MARK: - Live FileMaker Server integration tests (FILEMAKER_TESTS=1)

@Test func liveDatabaseNamesIncludesSampleDatabase() async throws {
    guard liveTestsEnabled() else { return }
    let names = try await liveServer().databaseNames()
    #expect(names.contains(sampleDB))
}

@Test func liveLayoutNamesIncludesSampleLayout() async throws {
    guard liveTestsEnabled() else { return }
    let names = try await liveServer().layoutNames(database: sampleDB)
    #expect(names.contains(sampleLayout))
}

@Test func liveLayoutInfoIncludesExpectedFields() async throws {
    guard liveTestsEnabled() else { return }
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

@Test func liveQuerySkipMaxReturnsExpectedRecordCounts() async throws {
    guard liveTestsEnabled() else { return }
    let fms = liveServer()

    let zeroQuery = FMPQuery(database: sampleDB, layout: sampleLayout, action: .findAll).maxRecords(0)
    let zeroResult = try await fms.query(zeroQuery)
    #expect(zeroResult.records.count == 0)

    let twoQuery = FMPQuery(database: sampleDB, layout: sampleLayout, action: .findAll).skipRecords(2).maxRecords(2)
    let twoResult = try await fms.query(twoQuery)
    #expect(twoResult.records.count == 2)
}

@Test func liveQueryFindAllReturnsRecordsMatchingLayout() async throws {
    guard liveTestsEnabled() else { return }
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

@Test func liveQueryFindInProgressReturnsMatchingStatus() async throws {
    guard liveTestsEnabled() else { return }
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

@Test func liveNewFindAndDeleteRoundTrip() async throws {
    guard liveTestsEnabled() else { return }
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
