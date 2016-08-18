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
internal let fmrsRelatedSetDefinition = "relatedset-definition"

let fmrsRecord = "record"
let fmrsField = "field"
let fmrsRelatedSet = "relatedset"

let fmrsData = "\(fmrs):data/text()"

public enum FMPFieldValue: CustomStringConvertible {
	case text(String), number(Double), container(String),
		date(String), time(String), timestamp(String)
	
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

public struct FMPDatabaseInfo {
	public let dateFormat: String
	public let timeFormat: String
	public let timeStampFormat: String
	public let recordCount: Int
	
	init(node: XElement) {
		dateFormat = node.getAttribute(name: "date-format") ?? "MM/dd/yyyy"
		timeFormat = node.getAttribute(name: "time-format") ?? "HH:mm:ss"
		timeStampFormat = node.getAttribute(name: "timestamp-format") ?? "MM/dd/yyyy HH:mm:ss"
		recordCount = Int(node.getAttribute(name: "total-count") ?? "0") ?? 0
	}
}

public struct FMPRecord {
	public enum RecordItem {
		case field(String, FMPFieldValue)
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
	
	public let recordId: Int
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

public struct FMPResultSet {
	public let databaseInfo: FMPDatabaseInfo
	public let layoutInfo: FMPLayoutInfo
	public let foundCount: Int
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
		let fieldTypes = self.layoutInfo.flattenedTypes
		self.records = resultSetNode.childElements.map { FMPRecord(node: $0, fieldTypes: fieldTypes) }
	}
}




