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

public struct FMPFieldInfo {
	public let name: String
	public let type: String
	public let valueList: String?
}

public struct FMPValueListItem {
	public let display: String
	public let value: String
}

public struct FMPDatabaseInfo {
	public let dateFormat: String
	public let timeFormat: String
	public let recordCount: Int
}

public struct FMPLayoutInfo {
	public let fields: [FMPFieldInfo]
	public let valueLists: [String:[FMPValueListItem]]
}

public struct FMPFieldData {
	public enum FieldType: CustomStringConvertible {
		case text(String), number(Double), container(String), date(String)
		
		init(value: String, type: String) {
			switch type {
			case "NUMBER":
				self = .number(Double(value) ?? 0.0)
			case "CONTAINER":
				self = .container(value)
			case "DATE":
				self = .date(value)
			default:
				self = .text(value)
			}
		}
		
		public var description: String {
			switch self {
			case .text(let s): return s
			case .number(let s): return String(s)
			case .container(let s): return s
			case .date(let s): return s
			}
		}
	}
	public let values: [FieldType]
	public var value: FieldType {
		guard let first = self.values.first else {
			return .text("")
		}
		return first
	}
	
	init(colElement: XElement, info: FMPFieldInfo) {
		guard case .nodeSet(let datas) = colElement.extract(path: fmpxrData, namespaces: fmpxrNamespaces) else {
			self.values = [FieldType]()
			return
		}
		self.values = datas.map { FieldType(value: $0.nodeValue ?? "", type: info.type) }
	}
}

public struct FMPRecord {
	public let recordId: Int
	public let fields: [FMPFieldData]
	
	init(rowElement: XElement, fieldInfos: [FMPFieldInfo]) {
		self.recordId = Int(rowElement.getAttribute(name: "RECORDID") ?? "0") ?? 0
		guard case .nodeSet(let cols) = rowElement.extract(path: fmpxrCol, namespaces: fmpxrNamespaces) else {
			self.fields = [FMPFieldData]()
			return
		}
		let columns = cols.flatMap { (node:XNode) -> XElement? in return node as? XElement }
		guard columns.count == fieldInfos.count else {
			self.fields = [FMPFieldData]()
			return
		}
		self.fields = zip(columns, fieldInfos).map { FMPFieldData(colElement: $0.0, info: $0.1) }
	}
}

public struct FMPResultSet {
	public let databaseInfo: FMPDatabaseInfo
	public let layoutInfo: FMPLayoutInfo
	public let records: [FMPRecord]
	
	public var recordCount: Int {
		return records.count
	}
	
	init(doc: XDocument, layoutInfo: FMPLayoutInfo?) {
		let databaseNode = doc.extractOne(path: fmpxrDatabase, namespaces: fmpxrNamespaces) as? XElement
		self.databaseInfo = FMPDatabaseInfo(dateFormat: databaseNode?.getAttribute(name: "DATEFORMAT") ?? "MM/DD/YYYY",
		                               timeFormat: databaseNode?.getAttribute(name: "TIMEFORMAT") ?? "HH:mm:ss",
		                               recordCount: Int(databaseNode?.getAttribute(name: "RECORDS") ?? "0") ?? 0)
		
		guard case .nodeSet(let fields) = doc.extract(path: fmpxrField, namespaces: fmpxrNamespaces) else {
			self.records = [FMPRecord]()
			self.layoutInfo = FMPLayoutInfo(fields: [FMPFieldInfo](), valueLists: [String : [FMPValueListItem]]())
			return
		}
		
		let fieldInfos: [FMPFieldInfo] = fields.flatMap { (node:XNode) -> XElement? in
				return node as? XElement
			}.flatMap {
				guard let fieldName = $0.getAttribute(name: "NAME"),
					let fieldType = $0.getAttribute(name: "TYPE") else {
						return nil
				}
				return FMPFieldInfo(name: fieldName, type: fieldType, valueList: nil)
			}
		
		if let preLay = layoutInfo {
			// have to order these so they match the field ordering in this result set
			// they do not normally match
			var dict = [String:FMPFieldInfo]()
			for info in preLay.fields {
				dict[info.name] = info
			}
			self.layoutInfo = FMPLayoutInfo(fields: fieldInfos.flatMap { dict[$0.name] }, valueLists: preLay.valueLists)
		} else {
			self.layoutInfo = FMPLayoutInfo(fields: fieldInfos, valueLists: [String : [FMPValueListItem]]())
		}
		
		guard case .nodeSet(let rows) = doc.extract(path: fmpxrRow, namespaces: fmpxrNamespaces) else {
			self.records = [FMPRecord]()
			return
		}
		
		var recs = [FMPRecord]()
		for row in rows {
			guard let row = row as? XElement else {
				continue
			}
			recs.append(FMPRecord(rowElement: row, fieldInfos: fieldInfos))
		}
		self.records = recs
	}
}
