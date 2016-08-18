//
//  FMPLayoutInfo.swift
//  PerfectFileMaker
//
//  Created by Kyle Jessup on 2016-08-17.
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

public enum FMPFieldType {
	case text, number, container, date, time, timestamp
	
	init(_ type: String) {
		switch type {
		case "number":
			self = .number
		case "container":
			self = .container
		case "date":
			self = .date
		case "time":
			self = .time
		case "timestamp":
			self = .timestamp
		default:
			self = .text
		}
	}
}

public struct FMPFieldDefinition {
	public let name: String
	public let type: FMPFieldType
	
	init(node: XElement) {
		self.name = node.getAttribute(name: "name") ?? ""
		self.type = FMPFieldType(node.getAttribute(name: "result") ?? "text")
	}
}

public enum FMPMetaDataItem {
	case fieldDefinition(FMPFieldDefinition)
	case relatedSetDefinition(String, [FMPFieldDefinition])
	
	init(node: XElement) {
		if node.nodeName == fmrsRelatedSetDefinition {
			self = .relatedSetDefinition(node.getAttribute(name: "table") ?? "", node.childElements.map { FMPFieldDefinition(node: $0) })
		} else {
			self = .fieldDefinition(FMPFieldDefinition(node: node))
		}
	}
}

public struct FMPLayoutInfo {
	public let fields: [FMPMetaDataItem]
	
	var flattenedTypes: [String:FMPFieldType] {
		let flattened = soFlat(fields: fields)
		var ret = [String:FMPFieldType]()
		for (n, v) in flattened {
			ret[n] = v
		}
		return ret
	}
	
	func flattenOne(item: FMPMetaDataItem) -> [(String, FMPFieldType)] {
		switch item {
		case .fieldDefinition(let def):
			return [(def.name, def.type)]
		case .relatedSetDefinition(let table, let fields):
			return soFlat(prefix: table, fields: fields)
		}
	}
	
	func soFlat(fields: [FMPMetaDataItem]) -> [(String, FMPFieldType)] {
		return fields.flatMap { self.flattenOne(item: $0) }
	}
	
	func soFlat(prefix: String,  fields: [FMPFieldDefinition]) -> [(String, FMPFieldType)] {
		return fields.map { ($0.name, $0.type) }
	}
	
	init(node: XElement) {
		self.fields = node.childElements.map { FMPMetaDataItem(node: $0) }
	}
}
