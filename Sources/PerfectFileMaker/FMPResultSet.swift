//
//  FMPResultSet.swift
//  PerfectFileMaker
//
//  Created by Kyle Jessup on 2016-08-03.
//	Copyright (C) 2016 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PerfectXML

let fmrs = "fmrs"
let fmrsNamespaces = [(fmrs, "http://www.filemaker.com/xml/fmresultset")]
let fmrsErrorCode = "/\(fmrs):fmresultset/\(fmrs):error/@code"
let fmrsResultSet = "/\(fmrs):fmresultset/\(fmrs):resultset"
let fmrsMetaData = "/\(fmrs):fmresultset/\(fmrs):metadata"
let fmrsDataSource = "/\(fmrs):fmresultset/\(fmrs):datasource"
let fmrsFieldDefinition = "field-definition"
let fmrsRelatedSetDefinition = "relatedset-definition"

let fmrsRecord = "record"
let fmrsField = "field"
let fmrsRelatedSet = "relatedset"

let fmrsData = "\(fmrs):data/text()"

/// A returned FileMaker field value.
public enum FMPFieldValue: CustomStringConvertible {
	/// A text field.
	case text(String)
	/// A numeric field.
	case number(Double)
	/// A container field.
	case container(String)
	/// A date field.
	case date(String)
	/// A time field.
	case time(String)
	/// A timestamp field.
	case timestamp(String)
	
	init(value: String, type: FMPFieldType) {
		switch type {
		case .number:
			self = .number(Double(value) ?? 0.0)
		case .container:
			self = .container(value)
		case .date:
			self = .date(value)
		case .time:
			self = .time(value)
		case .timestamp:
			self = .timestamp(value)
		case .text:
			self = .text(value)
		}
	}
	/// Returns the field value converted to String
	public var description: String {
		switch self {
		case .text(let s): return s
		case .number(let s): return String(s)
		case .container(let s): return s
		case .date(let s): return s
		case .time(let s): return s
		case .timestamp(let s): return s
		}
	}
}

/// Meta-information for a database.
public struct FMPDatabaseInfo {
	/// The date format indicated by the server.
	public let dateFormat: String
	/// The time format indicated by the server.
	public let timeFormat: String
	/// The timestamp format indicated by the server.
	public let timeStampFormat: String
	/// The total number of records in the database.
	public let recordCount: Int
	
	init(node: XElement) {
		dateFormat = node.getAttribute(name: "date-format") ?? "MM/dd/yyyy"
		timeFormat = node.getAttribute(name: "time-format") ?? "HH:mm:ss"
		timeStampFormat = node.getAttribute(name: "timestamp-format") ?? "MM/dd/yyyy HH:mm:ss"
		recordCount = Int(node.getAttribute(name: "total-count") ?? "0") ?? 0
	}
}

/// An individual result set record.
public struct FMPRecord {
	/// A type of record item.
	public enum RecordItem {
		/// An individual field.
		case field(String, FMPFieldValue)
		/// A related set containing a list of related records.
		case relatedSet(String, [FMPRecord])
		
		init(node: XElement, fieldTypes: [String:FMPFieldType]) {
			let name: String
			if node.nodeName == fmrsField {
				name = node.getAttribute(name: "name") ?? ""
			} else {
				name = node.getAttribute(name: "table") ?? ""
			}
			let type = fieldTypes[name] ?? .text
			if node.nodeName == fmrsField {
				let data = node.getElementsByTagName("data").first
				self = .field(name, FMPFieldValue(value: data?.nodeValue ?? "", type: type))
			} else {
				self = .relatedSet(name, node.childElements.map { FMPRecord(node: $0, fieldTypes: fieldTypes) })
			}
		}
		
		// this can only be field
		init(setName: String, node: XElement, fieldTypes: [String:FMPFieldType]) {
			let name = node.getAttribute(name: "name") ?? ""
			let type = fieldTypes[setName + "::" + name] ?? .text
			let data = node.getElementsByTagName("data").first
			self = .field(name, FMPFieldValue(value: data?.nodeValue ?? "", type: type))
		}
	}
	/// The record id.
	public let recordId: Int
	/// The contained record items keyed by name.
	public let elements: [String:RecordItem]
	
	init(node: XElement, fieldTypes: [String:FMPFieldType]) {
		self.recordId = Int(node.getAttribute(name: "record-id") ?? "-1") ?? -1
		var elements = [String:RecordItem]()
		for e in node.childElements {
			let item = RecordItem(node: e, fieldTypes: fieldTypes)
			let name: String
			switch item {
			case .field(let n, _):
				name = n
			case .relatedSet(let n, _):
				name = n
			}
			elements[name] = item
		}
		self.elements = elements
	}
	
	init(setName: String, node: XElement, fieldTypes: [String:FMPFieldType]) {
		self.recordId = Int(node.getAttribute(name: "record-id") ?? "-1") ?? -1
		var elements = [String:RecordItem]()
		for e in node.childElements {
			let item = RecordItem(setName: setName, node: e, fieldTypes: fieldTypes)
			let name: String
			switch item {
			case .field(let n, _):
				name = n
			case .relatedSet(let n, _): // inconceivable!
				name = n
			}
			elements[name] = item
		}
		self.elements = elements
	}
}

/// The result set produced by a query.
public struct FMPResultSet {
	/// Database meta-info.
	public let databaseInfo: FMPDatabaseInfo
	/// Layout meta-info.
	public let layoutInfo: FMPLayoutInfo
	/// The number of records found by the query.
	public let foundCount: Int
	/// The list of records produced by the query.
	public let records: [FMPRecord]
	
	init?(doc: XDocument) {
		guard let databaseNode = doc.extractOne(path: fmrsDataSource, namespaces: fmrsNamespaces) as? XElement,
			let metaDataNode = doc.extractOne(path: fmrsMetaData, namespaces: fmrsNamespaces) as? XElement,
			let resultSetNode = doc.extractOne(path: fmrsResultSet, namespaces: fmrsNamespaces) as? XElement else {
			return nil
		}
		
		self.databaseInfo = FMPDatabaseInfo(node: databaseNode)
		self.layoutInfo = FMPLayoutInfo(node: metaDataNode)
		self.foundCount = Int(resultSetNode.getAttribute(name: "count") ?? "") ?? 0
		let fieldTypes = self.layoutInfo.fieldsByName
		self.records = resultSetNode.childElements.map { FMPRecord(node: $0, fieldTypes: fieldTypes) }
	}
}




