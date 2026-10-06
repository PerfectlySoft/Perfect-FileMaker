# Perfect - FileMaker Server Connector

<p align="center">
    <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B%20%7C%20Linux-lightgray.svg?style=flat" alt="Platforms macOS 12+ | Linux">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg?style=flat" alt="License Apache 2.0"></a>
</p>

This project provides access to FileMaker Server databases using the classic XML Custom Web Publishing (CWP) interface (the `fmresultset` grammar) — listing databases, layouts, and fields, and running `find`/`findAll` queries. It was written to be stand-alone and does not need to be run as part of a Perfect server application.

**Modernized for Swift 6.** A real query-injection gap in the original percent-encoder was found
and fixed during modernization: search values and names are now percent-encoded with a strict
allow-list, so a value containing `&` or `=` can't add query directives. See the
[4.0.0 release notes](../../releases/tag/4.0.0) if you're evaluating this as a trust boundary.

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.

## Requirements

- Swift **6.2** or newer (`swift-tools-version: 6.2`)
- **macOS 12** or later, or **Linux**. On Linux, install `libxml2-dev` and `pkg-config` for Perfect-XML (`sudo apt-get install libxml2-dev pkg-config`); on macOS the SDK's libxml2 is used and nothing extra is needed.

CI builds and tests on Linux (Swift 6.2 and 6.4) and macOS (Xcode 26.0.1 and 26.6), in debug and release, with warnings treated as errors. There is no FileMaker Server in CI, so it runs the tests that don't need one; see [Testing](#testing).

## Building

```swift
.package(url: "https://github.com/PerfectlySoft/Perfect-FileMaker.git", from: "4.0.0")
```

and add `.product(name: "PerfectFileMaker", package: "Perfect-FileMaker")` to your target's dependencies.

## Dependencies

- [Perfect-XML](https://github.com/PerfectlySoft/Perfect-XML) 4.0.0 or later — used to parse the `fmresultset` XML responses. Every request, including `layoutInfo` (sent as `-view`), asks for the `fmresultset` grammar.

Networking is done directly via Foundation's `URLSession`/`URLRequest` — there is **no Perfect-CURL dependency** and no libcurl requirement of its own (on Linux, FoundationNetworking itself links libcurl, which the official Swift images already include). Query requests are deliberately sent as `POST` rather than `GET`, to avoid credential-adjacent query values leaking into URL logs, with a default 5-second request timeout and forced connection closure — added specifically to prevent FileMaker Web Publishing Engine session buildup under crawl-style load.

Note: only the `fmresultset` grammar is implemented. `layoutInfo` reads the field names, field result types and portal (related-set) fields from the `fmresultset` metadata. The `FMPXMLLAYOUT` grammar (value lists and other layout details) and the `FMPXMLRESULT` grammar are deliberately unimplemented, matching the original PerfectlySoft library.

## Examples

To utilize this package, ```import PerfectFileMaker```.

The public API is fully `async`/`await` — there are no completion-handler closures.

### List Available Databases

This snippet connects to the server and has it list all of the hosted databases.

```swift
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
do {
	let names = try await fms.databaseNames()
	for name in names {
		print("Got a database name \(name)")
	}
} catch FMPError.serverError(let code, let msg) {
	print("Got a server error \(code) \(msg)")
} catch let e {
	print("Got an unexpected error \(e)")
}
```

### List Available Layouts

List all of the layouts in a particular database.

```swift
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
do {
	let names = try await fms.layoutNames(database: "FMServer_Sample")
	for name in names {
		print("Got a layout name \(name)")
	}
} catch let e {
	print("Got an unexpected error \(e)")
}
```

### List Field On Layout

List all of the field names on a particular layout.

```swift
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
do {
	let layoutInfo = try await fms.layoutInfo(database: "FMServer_Sample", layout: "Task Details")
	let fieldsByName = layoutInfo.fieldsByName
	for (name, value) in fieldsByName {
		print("Field \(name) = \(value)")
	}
} catch let e {
	print("Got an unexpected error \(e)")
}
```

### Find All Records

Perform a findall and print all field names and values.

```swift
let query = FMPQuery(database: "FMServer_Sample", layout: "Task Details", action: .findAll)
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
do {
	let resultSet = try await fms.query(query)
	let fields = resultSet.layoutInfo.fields
	let records = resultSet.records
	let recordCount = records.count
	for i in 0..<recordCount {
		let rec = records[i]
		for field in fields {
			switch field {
			case .fieldDefinition(let def):
				let fieldName = def.name
				if let fnd = rec.elements[fieldName], case .field(_, let fieldValue) = fnd {
					print("Normal field: \(fieldName) = \(fieldValue)")
				}
			case .relatedSetDefinition(let name, _):
				guard let fnd = rec.elements[name], case .relatedSet(_, let relatedRecs) = fnd else {
					continue
				}
				print("Relation: \(name)")
				for relatedRec in relatedRecs {
					for relatedRow in relatedRec.elements.values {
						if case .field(let fieldName, let fieldValue) = relatedRow {
							print("\tRelated field: \(fieldName) = \(fieldValue)")
						}
					}
				}
			}
		}
	}
} catch let e {
	print("Got an unexpected error \(e)")
}
```

### Find All Records With Skip &amp; Max

To add skip and max, the query above would be amended as follows:

```swift
// Skip two records and return a max of two records.
let query = FMPQuery(database: "FMServer_Sample", layout: "Task Details", action: .findAll)
	.skipRecords(2).maxRecords(2)
...
```

### Find Records Where "Status" Is "In Progress"

Find all records where the field "Status" has the value of "In Progress".

```swift
let qfields = [FMPQueryFieldGroup(fields: [FMPQueryField(name: "Status", value: "In Progress")])]
let query = FMPQuery(database: "FMServer_Sample", layout: "Task Details", action: .find)
	.queryFields(qfields)
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
do {
	let resultSet = try await fms.query(query)
	let fields = resultSet.layoutInfo.fields
	let records = resultSet.records
	let recordCount = records.count
	for i in 0..<recordCount {
		let rec = records[i]
		for field in fields {
			switch field {
			case .fieldDefinition(let def):
				let fieldName = def.name
				if let fnd = rec.elements[fieldName], case .field(_, let fieldValue) = fnd {
					print("Normal field: \(fieldName) = \(fieldValue)")
					if fieldName == "Status", case .text(let tstStr) = fieldValue {
						print("Status == \(tstStr)")
					}
				}
			case .relatedSetDefinition(let name, _):
				guard let fnd = rec.elements[name], case .relatedSet(_, let relatedRecs) = fnd else {
					continue
				}
				print("Relation: \(name)")
				for relatedRec in relatedRecs {
					for relatedRow in relatedRec.elements.values {
						if case .field(let fieldName, let fieldValue) = relatedRow {
							print("\tRelated field: \(fieldName) = \(fieldValue)")
						}
					}
				}
			}
		}
	}
} catch let e {
	print("Got an unexpected error \(e)")
}
```

## Migrating from 3.x

4.0.0 is a major release; the [release notes](../../releases/tag/4.0.0) list every change. The ones most likely to need attention:

* **Toolchain and platforms.** Swift tools 6.2 is required, and the package declares macOS 12+ (3.x declared no platforms). Linux builds need `libxml2-dev` and `pkg-config`; libcurl is no longer used.
* **`async`/`await` instead of callbacks.** `databaseNames()`, `layoutNames(database:)`, `layoutInfo(database:layout:)` and `query(_:)` are `async throws` and return their result directly. Replace `fms.query(q) { response in let rs = try response() ... }` with `let rs = try await fms.query(q)`.
* **Perfect-CURL and PerfectLib are gone.** Requests use Foundation's `URLSession`. `FileMakerServer.init` gains optional `useTLS:`, `urlSession:` and `defaultTimeout:` parameters; existing four-argument calls still compile.
* **5-second request timeout.** Each request now times out after 5 seconds by default (3.x set no timeout of its own). Pass a longer `defaultTimeout:` for servers or queries that need it.
* **Stricter escaping.** Names and values are percent-encoded except for `A-Z a-z 0-9 - . _ ~`, which closes a query-injection hole. Comparison operators (`==`, `>`, `>=`, `<`, `<=`) are now sent literally and only the value is encoded; 3.x percent-encoded the operator along with the value. Query strings are covered by tests; there was no FileMaker Server to confirm them against.
* **Plain-HTTP credentials are logged.** Sending a user name and password without TLS (`useTLS` unset and port not 443) still works but writes a warning to standard error.
* **`Sendable`.** The public types are `Sendable`. `FMPQueryField` is `@unchecked Sendable` because its `value` is `Any`: pass only strings and numbers.

## Testing

```
swift test
```

The query-building and request/response tests run anywhere; the request tests use a mocked `URLSession`. The live tests run against the `FMServer_Sample` database on a real FileMaker Server and are skipped unless `FILEMAKER_TESTS=1` is set, with `FILEMAKER_HOST`, `FILEMAKER_PORT`, `FILEMAKER_USER` and `FILEMAKER_PASSWORD` describing the server.
