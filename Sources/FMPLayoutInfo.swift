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

/// One of the possible FileMaker field types.
public enum FMPFieldType {
	/// A text field.
	case text
	/// A numeric field.
	case number
	/// A container field.
	case container
	/// A date field.
	case date
	/// A time field.
	case time
	/// A timestamp field.
	case timestamp
	
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

/// A FileMaker field definition. Indicates a field name and type.
public struct FMPFieldDefinition {
	/// The field name.
	public let name: String
	/// The field type.
	public let type: FMPFieldType
	
	init(node: XElement) {
		self.name = node.getAttribute(name: "name") ?? ""
		self.type = FMPFieldType(node.getAttribute(name: "result") ?? "text")
	}
}

/// Represents either an individual field definition or a related (portal) definition.
public enum FMPMetaDataItem {
	/// An individual field.
	case fieldDefinition(FMPFieldDefinition)
	/// A related set. Indicates the portal name and its contained fields.
	case relatedSetDefinition(String, [FMPFieldDefinition])
	
	init(node: XElement) {
		if node.nodeName == fmrsRelatedSetDefinition {
			self = .relatedSetDefinition(node.getAttribute(name: "table") ?? "", node.childElements.map { FMPFieldDefinition(node: $0) })
		} else {
			self = .fieldDefinition(FMPFieldDefinition(node: node))
		}
	}
}

/// Represents meta-information about a particular layout.
public struct FMPLayoutInfo {
	/// Each field or related set as a list.
	public let fields: [FMPMetaDataItem]
	/// Each field or related set keyed by name.
	public let fieldsByName: [String:FMPFieldType]
	
	init(node: XElement) {
		self.fields = node.childElements.map { FMPMetaDataItem(node: $0) }
		
		func flattenOne(item: FMPMetaDataItem) -> [(String, FMPFieldType)] {
			switch item {
			case .fieldDefinition(let def):
				return [(def.name, def.type)]
			case .relatedSetDefinition(let table, let fields):
				return soFlat(prefix: table, fields: fields)
			}
		}
		
		func soFlat(fields: [FMPMetaDataItem]) -> [(String, FMPFieldType)] {
			return fields.flatMap { flattenOne(item: $0) }
		}
		
		func soFlat(prefix: String,  fields: [FMPFieldDefinition]) -> [(String, FMPFieldType)] {
			return fields.map { ($0.name, $0.type) }
		}
		
		let flattened = soFlat(fields: self.fields)
		var ret = [String:FMPFieldType]()
		for (n, v) in flattened {
			ret[n] = v
		}
		self.fieldsByName = ret
	}
}
