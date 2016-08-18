//
//  FMPQuery.swift
//  PerfectFileMaker
//
//  Created by Kyle Jessup on 2016-08-02.
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

import PerfectLib

public enum FMPAction: CustomStringConvertible {
	case find, findAll, findAny
	case new, edit, delete, duplicate
	public var description: String {
		switch self {
		case .find: return "-findquery"
		case .findAll: return "-findall"
		case .findAny: return "-findany"
		case .new: return "-new"
		case .edit: return "-edit"
		case .delete: return "-delete"
		case .duplicate: return "-dup"
		}
	}
}

public enum FMPSortOrder: CustomStringConvertible {
	case ascending, descending, custom
	public var description: String {
		switch self {
		case .ascending: return "ascend"
		case .descending: return "descend"
		case .custom: return "custom"
		}
	}
}

public enum FMPLogicalOp {
	case and, or, not
}

public enum FMPFieldOp {
	case equal, contains, beginsWith, endsWith, greaterThan, greaterThanEqual, lessThan, lessThanEqual
}

public struct FMPQueryField {
	public let name: String
	public let value: Any
	public let op: FMPFieldOp
	
	var valueWithOp: String {
		switch op {
		case .equal: return "==\(value)"
		case .contains: return "==*\(value)*"
		case .beginsWith: return "==\(value)*"
		case .endsWith: return "==*\(value)"
		case .greaterThan: return ">\(value)"
		case .greaterThanEqual: return ">=\(value)"
		case .lessThan: return "<\(value)"
		case .lessThanEqual: return "<=\(value)"
		}
	}
	
	public init(name: String, value: Any, op: FMPFieldOp) {
		self.name = name
		self.value = value
		self.op = op
	}
	
	public init(name: String, value: Any) {
		self.init(name: name, value: value, op: .beginsWith)
	}
}

public struct FMPQueryFieldGroup {
	public let op: FMPLogicalOp
	public let fields: [FMPQueryField]
	
	public init(op: FMPLogicalOp, fields: [FMPQueryField]) {
		self.op = op
		self.fields = fields
	}
	
	public init(fields: [FMPQueryField]) {
		self.init(op: .and, fields: fields)
	}
	
	var simpleFieldsString: String {
		return fields.map {
			let vstr = "\($0.value)"
			return "\($0.name.stringByEncodingURL)=\(vstr.stringByEncodingURL)"
		}.joined(separator: "&")
	}
}

public struct FMPSortField {
	public let name: String
	public let order: FMPSortOrder
	
	public init(name: String, order: FMPSortOrder) {
		self.name = name
		self.order = order
	}
	
	public init(name: String) {
		self.init(name: name, order: .ascending)
	}
}

public let fmpNoRecordId = -1
public let fmpAllRecords = -1

public struct FMPQuery: CustomStringConvertible {
	
	let database: String
	let layout: String
	let action: FMPAction
	let queryFields: [FMPQueryFieldGroup]
	let sortFields: [FMPSortField]
	let recordId: Int
	let preSortScripts: [String]
	let preFindScripts: [String]
	let postFindScripts: [String]
	let responseLayout: String
	let responseFields: [String]
	let maxRecords: Int
	let skipRecords: Int
	
	public init(database: String, layout: String, action: FMPAction) {
		queryFields = [FMPQueryFieldGroup]()
		sortFields = [FMPSortField]()
		recordId = fmpNoRecordId
		preSortScripts = [String]()
		preFindScripts = [String]()
		postFindScripts = [String]()
		responseLayout = ""
		responseFields = [String]()
		maxRecords = fmpAllRecords
		skipRecords = 0
		self.database = database
		self.layout = layout
		self.action = action
	}
	
	init(queryFields: [FMPQueryFieldGroup],
	     sortFields: [FMPSortField],
	     recordId: Int,
	     preSortScripts: [String],
	     preFindScripts: [String],
	     postFindScripts: [String],
	     responseLayout: String,
	     responseFields: [String],
	     maxRecords: Int,
	     skipRecords: Int,
	     action: FMPAction,
	     database: String,
	     layout: String) {
		
		self.queryFields = queryFields
		self.sortFields = sortFields
		self.recordId = recordId
		self.preSortScripts = preSortScripts
		self.preFindScripts = preFindScripts
		self.postFindScripts = postFindScripts
		self.responseLayout = responseLayout
		self.responseFields = responseFields
		self.maxRecords = maxRecords
		self.skipRecords = skipRecords
		self.action = action
		self.database = database
		self.layout = layout
	}
	
	public func recordId(_ recordId: Int) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func queryFields(_ queryFields: [FMPQueryFieldGroup]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func sortFields(_ sortFields: [FMPSortField]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func preSortScripts(_ preSortScripts: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func preFindScripts(_ preFindScripts: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func postFindScripts(_ postFindScripts: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func responseLayout(_ responseLayout: String) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func responseFields(_ responseFields: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func maxRecords(_ maxRecords: Int) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	public func skipRecords(_ skipRecords: Int) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	
	func maybeAmp(_ s: String) -> String {
		if s.isEmpty {
			return ""
		}
		return s + "&"
	}
	
	var fieldCount: Int {
		return queryFields.reduce(0) {
			partialResult, grp -> Int in
			return partialResult + grp.fields.count
		}
	}
	
	var dbLayString: String {
		return "-db=\(database.stringByEncodingURL)&-lay=\(layout.stringByEncodingURL)&"
	}
	
	var sortFieldsString: String {
		var colNum = 1
		return sortFields.map { field -> String in
			let ret = "-sortfield.\(colNum)=\(field.name.stringByEncodingURL)&-sortorder.\(colNum)=\(field.order)"
			colNum += 1
			return ret
		}.joined(separator: "&")
	}
	
	var responseFieldsString: String {
		return responseFields.map { "-field=\($0.stringByEncodingURL)" }.joined(separator: "&")
	}
	
	var scriptsString: String {
		let preSorts = preSortScripts.map { "-script.presort=\($0.stringByEncodingURL)" }.joined(separator: "&")
		let preFinds = preFindScripts.map { "-script.prefind=\($0.stringByEncodingURL)" }.joined(separator: "&")
		let postFinds = postFindScripts.map { "-script=\($0.stringByEncodingURL)" }.joined(separator: "&")
		return maybeAmp(preSorts) + maybeAmp(preFinds) + postFinds
	}
	
	var maxSkipString: String{
		return "-skip=\(skipRecords)&-max=\(maxRecords == fmpAllRecords ? "all" : String(maxRecords))"
	}
	
	var recidString: String {
		if recordId != fmpNoRecordId && action != .findAny {
			return "-recid=\(recordId)"
		}
		return ""
	}
	
	var responseLayoutString: String {
		if responseLayout.isEmpty {
			return ""
		}
		return "-lay.response=\(responseLayout.stringByEncodingURL)"
	}
	
	var actionString: String {
		return "\(action)"
	}
	
	var simpleFieldsString: String {
		return queryFields.map {
			$0.simpleFieldsString
		}.joined(separator: "&")
	}
	
	var compoundQueryString: String {
		var num = 0
		var segments = [String]()
		for group in queryFields {
			switch group.op {
			case .and:
				let str = "(\(group.fields.map { _ in num += 1 ; return "q\(num)" }.joined(separator: ",")))"
				segments.append(str)
			case .or:
				let str = "\(group.fields.map { _ in num += 1 ; return "(q\(num))" }.joined(separator: ";"))"
				segments.append(str)
			case .not:
				let str = "!(\(group.fields.map { _ in num += 1 ; return "q\(num)" }.joined(separator: ",")))"
				segments.append(str)
			}
		}
		return "-query=\(segments.joined(separator: ";").stringByEncodingURL)"
	}
	
	var compoundFieldsString: String {
		var num = 0
		var segments = [String]()
		for group in queryFields {
			let str = group.fields.map {
				num += 1
				return "-q\(num)=\($0.name.stringByEncodingURL)&-q\(num).value=\($0.valueWithOp.stringByEncodingURL)"
			}.joined(separator: "&")
			segments.append(str)
		}
		return segments.joined(separator: "&")
	}
	
	public var description: String {
		return queryString
	}
	
	public var queryString: String {
		let starter = dbLayString +
			maybeAmp(scriptsString) +
			maybeAmp(responseLayoutString)
		switch action {
		case .delete, .duplicate:
			return starter +
				maybeAmp(recidString) + actionString
		case .edit:
			return starter +
				maybeAmp(recidString) +
				maybeAmp(simpleFieldsString) + actionString
		case .new:
			return starter +
				maybeAmp(simpleFieldsString) + actionString
		case .findAny:
			return starter + actionString
		case .findAll:
			return starter +
				maybeAmp(sortFieldsString) +
				maybeAmp(maxSkipString) + actionString
		case .find:
			if recordId != fmpNoRecordId {
				return starter +
					maybeAmp(recidString) + "-find"
			}
			return starter +
				maybeAmp(sortFieldsString) +
				maybeAmp(maxSkipString) +
				maybeAmp(compoundQueryString) +
				maybeAmp(compoundFieldsString) + actionString
		}
	}
}
