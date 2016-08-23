# Perfect - FileMaker Server Connector

[![Perfect logo](http://www.perfect.org/github/Perfect_GH_header_854.jpg)](http://perfect.org/get-involved.html)

[![Perfect logo](http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg)](https://github.com/PerfectlySoft/Perfect)
[![Perfect logo](http://www.perfect.org/github/Perfect_GH_button_2_Git.jpg)](https://gitter.im/PerfectlySoft/Perfect)
[![Perfect logo](http://www.perfect.org/github/Perfect_GH_button_3_twit.jpg)](https://twitter.com/perfectlysoft)
[![Perfect logo](http://www.perfect.org/github/Perfect_GH_button_4_slack.jpg)](http://perfect.ly)


[![Swift 3.0](https://img.shields.io/badge/Swift-3.0-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![Platforms OS X | Linux](https://img.shields.io/badge/Platforms-OS%20X%20%7C%20Linux%20-lightgray.svg?style=flat)](https://developer.apple.com/swift/)
[![License Apache](https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat)](http://perfect.org/licensing.html)
[![Twitter](https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat)](http://twitter.com/PerfectlySoft)
[![Join the chat at https://gitter.im/PerfectlySoft/Perfect](https://img.shields.io/badge/Gitter-Join%20Chat-brightgreen.svg)](https://gitter.im/PerfectlySoft/Perfect?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
[![Slack Status](http://perfect.ly/badge.svg)](http://perfect.ly)
[![GitHub version](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-FileMaker.svg)](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-FileMaker)

This project provides access to FileMaker Server databases using the XML Web publishing interface.

This package builds with Swift Package Manager and is part of the [Perfect](https://github.com/PerfectlySoft/Perfect) project. It was written to be stand-alone and so does not need to be run as part of a Perfect server application.

Ensure you have installed and activated the latest Swift 3.0 tool chain.

## Linux Build Notes

Ensure that you have installed curl and libxml2.

```
sudo apt-get install libcurl4-openssl-dev libxml2-dev
```

## Building

Add this project as a dependency in your Package.swift file.

```
.Package(url: "https://github.com/PerfectlySoft/Perfect-FileMaker.git", versions: Version(0,0,0)..<Version(10,0,0))
```

## Examples

To utilize this package, ```import PerfectFileMaker```.

### List Available Databases

This snippet connects to the server and has it list all of the hosted databases.

```swift
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
fms.databaseNames {
	result in
	do {
		// Get the list of names
		let names = try result()
		for name in names {
			print("Got a database name \(name)")
		}
	} catch FMPError.serverError(let code, let msg) {
		print("Got a server error \(code) \(msg)")
	} catch let e {
		print("Got an unexpected error \(e)")
	}
}
```

### List Available Layouts

List all of the layouts in a particular database.

```swift
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
fms.layoutNames(database: "FMServer_Sample") {
	result in
	guard let names = try? result() else {
		return // got an error
	}
	for name in names {
		print("Got a layout name \(name)")
	}
}
```

### List Field On Layout

List all of the field names on a particular layout.

```swift
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
fms.layoutInfo(database: "FMServer_Sample", layout: "Task Details") {
	result in
	guard let layoutInfo = try? result() else {
		return // error
	}
	let fieldsByName = layoutInfo.fieldsByName
	for (name, value) in fieldsByName {
		print("Field \(name) = \(value)")
	}
}
```

### Find All Records

Perform a findall and print all field names and values.

```swift
let query = FMPQuery(database: "FMServer_Sample", layout: "Task Details", action: .findAll)
let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
fms.query(query) {
	result in
	guard let resultSet = try? result() else {
		return // error
	}
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
fms.query(query) {
	result in
	guard let resultSet = try? result() else {
		return // error
	}
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
					if name == "Status", case .text(let tstStr) = fieldValue {
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
}
```
