# Perfect - FileMaker Server Connector

<p align="center">
    <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B-lightgray.svg?style=flat" alt="Platforms macOS 12+">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg?style=flat" alt="License Apache 2.0"></a>
</p>

This project provides access to FileMaker Server databases using the classic XML Custom Web Publishing (CWP) interface (the `fmresultset` grammar) — listing databases, layouts, and fields, and running `find`/`findAll` queries. It was written to be stand-alone and does not need to be run as part of a Perfect server application.

**Modernized for Swift 6.** A real query-injection gap in the original percent-encoder was found
and fixed during modernization — see the security note in the changelog/commit history if you're
evaluating this as a trust boundary.

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.

## Requirements

- Swift tools version **6.2** (see `Package.swift`'s `swift-tools-version`)
- **macOS 12** or later — this is the only platform formally declared in `Package.swift`'s `platforms` array

The source still guards its networking import with `#if canImport(FoundationNetworking)` for portability, but Linux is not currently a declared/supported SPM platform for this package — treat Linux support as unverified rather than assume the old Linux build notes below still apply.

## Building

```swift
.package(url: "https://github.com/PerfectlySoft/Perfect-FileMaker.git", branch: "main")
```

This package's own `Package.swift` resolves its [Perfect-XML](https://github.com/PerfectlySoft/Perfect-XML) dependency the same way (`.package(url:, branch: "main")`) — no monorepo layout is required to build either repo.

## Dependencies

- [Perfect-XML](https://github.com/PerfectlySoft/Perfect-XML) — used for parsing the `fmresultset` and `FMPXMLLAYOUT` XML responses.

Networking is done directly via Foundation's `URLSession`/`URLRequest` — there is **no Perfect-CURL dependency** and no libcurl requirement. Query requests are deliberately sent as `POST` rather than `GET`, to avoid credential-adjacent query values leaking into URL logs, with a default 5-second request timeout and forced connection closure — added specifically to prevent FileMaker Web Publishing Engine session buildup under crawl-style load.

Note: the classic `FMPXMLLAYOUT` grammar (full layout/value-list introspection beyond field names) is deliberately unimplemented, matching the original PerfectlySoft library's behavior — this is a known, intentional gap rather than an oversight.

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
