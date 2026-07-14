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

import Foundation

/// Percent-encodes every byte outside a strict RFC-3986-unreserved-only
/// allow-list (`A-Za-z0-9-._~`) — deliberately narrower than
/// `Foundation`'s `CharacterSet.urlQueryAllowed` (which lets `!$&'()*+,;=`
/// through untouched) and than the original `PerfectLib.stringByEncodingURL`
/// this replaces (which left `& = ! ( ) * ;` unescaped). FileMaker's
/// classic XML Web Publishing query grammar treats exactly those
/// characters as structurally significant (`-q1=Name&-q1.value=Value`,
/// compound queries like `-query=(q1,q2);(q3)`) — an unescaped `&` in a
/// user-supplied search value could otherwise smuggle extra query
/// directives into the request. Since the whole query string is POSTed
/// as `application/x-www-form-urlencoded`, over-encoding here is
/// invisible to FileMaker's own parser after its decode step, so erring
/// toward escaping more than strictly necessary is safe, not lossy.
extension String {
	var fmpEscaped: String {
		var result = ""
		result.reserveCapacity(utf8.count)
		for byte in utf8 {
			switch byte {
			case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, // A-Z a-z 0-9
				 0x2D, 0x2E, 0x5F, 0x7E:                // - . _ ~
				result.append(Character(UnicodeScalar(byte)))
			default:
				result += String(format: "%%%02X", byte)
			}
		}
		return result
	}
}

/// A database action.
public enum FMPAction: CustomStringConvertible, Sendable {
	/// Perform a search given the current query.
	case find
	/// Find all records in the database.
	case findAll
	/// Find and retrieve a random record.
	case findAny
	/// Create a new record given the current query data.
	case new
	/// Edit (update) the record indicated by the record id with the current query fields/values.
	case edit
	/// Delete the record indicated by the current record id.
	case delete
	/// Duplicate the record indicated by the current record id.
	case duplicate
	
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

/// A record sort order.
public enum FMPSortOrder: CustomStringConvertible, Sendable {
	/// Sort the records by the indicated field in ascending order.
	case ascending
	/// Sort the records by the indicated field in descending order.
	case descending
	/// Sort the records by the indicated field in a custom order.
	case custom
	public var description: String {
		switch self {
		case .ascending: return "ascend"
		case .descending: return "descend"
		case .custom: return "custom"
		}
	}
}

/// A sort field indicator.
public struct FMPSortField: Sendable {
	/// The name of the field on which to sort.
	public let name: String
	/// A field sort order.
	public let order: FMPSortOrder
	/// Initialize with a field name and sort order.
	public init(name: String, order: FMPSortOrder) {
		self.name = name
		self.order = order
	}
	/// Initialize with a field name using the default FMPSortOrder.ascending sort order.
	public init(name: String) {
		self.init(name: name, order: .ascending)
	}
}

/// An individual field search operator.
public enum FMPFieldOp: Sendable {
	case equal
	case contains
	case beginsWith
	case endsWith
	case greaterThan
	case greaterThanEqual
	case lessThan
	case lessThanEqual
}

/// An individual query field.
///
/// `@unchecked Sendable`: `value: Any` can't be verified Sendable at
/// compile time. In practice callers only ever pass primitive/`String`
/// values here (matching every real usage in this library and its
/// tests) — there's no stored mutable reference type this could hide.
public struct FMPQueryField: @unchecked Sendable {
	/// The name of the field.
	public let name: String
	/// The value for the field.
	public let value: Any
	/// The search operator.
	public let op: FMPFieldOp
	/// Initialize with a name, value and operator.
	public init(name: String, value: Any, op: FMPFieldOp = .beginsWith) {
		self.name = name
		self.value = value
		self.op = op
	}
	
	/// The operator token is always-ASCII, fixed FileMaker query syntax —
	/// never user data — and stays unencoded. Only the actual comparison
	/// value is percent-encoded, and only once: encoding the operator
	/// characters themselves (`> < = *`) here and relying on the call
	/// site to encode this whole string a second time was the original
	/// bug (see `FMPQuery.swift`'s `compoundFieldsString`) — under
	/// `PerfectLib`'s old encoder, `.greaterThan`/`.lessThanEqual`/etc.
	/// (which embed `<`/`>`/`=`, characters that encoder did escape)
	/// produced mangled, broken queries. Never feed operator syntax into
	/// the encoder.
	var valueWithOp: String {
		let encodedValue = "\(value)".fmpEscaped
		switch op {
		case .equal: return "==\(encodedValue)"
		case .contains: return "==*\(encodedValue)*"
		case .beginsWith: return "==\(encodedValue)*"
		case .endsWith: return "==*\(encodedValue)"
		case .greaterThan: return ">\(encodedValue)"
		case .greaterThanEqual: return ">=\(encodedValue)"
		case .lessThan: return "<\(encodedValue)"
		case .lessThanEqual: return "<=\(encodedValue)"
		}
	}
}

/// A logical operator used with query field groups.
public enum FMPLogicalOp: Sendable {
	case and, or, not
}

/// A group of query fields.
public struct FMPQueryFieldGroup: Sendable {
	/// The logical operator for the field group.
	public let op: FMPLogicalOp
	/// The list of fiedls in the group.
	public let fields: [FMPQueryField]
	/// Initialize with an operator and field list.
	/// The default logical operator is FMPLogicalOp.and.
	public init(fields: [FMPQueryField], op: FMPLogicalOp = .and) {
		self.op = op
		self.fields = fields
	}
	
	var simpleFieldsString: String {
		return fields.map {
			let vstr = "\($0.value)"
			return "\($0.name.fmpEscaped)=\(vstr.fmpEscaped)"
		}.joined(separator: "&")
	}
}

/// Indicates an invalid record id.
public let fmpNoRecordId = -1
/// Indicates no max records value.
public let fmpAllRecords = -1

/// An individual query & database action.
public struct FMPQuery: CustomStringConvertible, Sendable {
	
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
	
	/// Initialize with a database name, layout name & database action.
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
	
	/// Sets the record id and returns the adjusted query.
	public func recordId(_ recordId: Int) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Adds the query fields and returns the adjusted query.
	public func queryFields(_ queryFields: [FMPQueryFieldGroup]) -> FMPQuery {
		return FMPQuery(queryFields: self.queryFields + queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Adds the query fields and returns the adjusted query.
	public func queryFields(_ queryFields: [FMPQueryField]) -> FMPQuery {
		return FMPQuery(queryFields: self.queryFields + [FMPQueryFieldGroup(fields: queryFields)], sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Adds the sort fields and returns the adjusted query.
	public func sortFields(_ sortFields: [FMPSortField]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: self.sortFields + sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Adds the indicated pre-sort scripts and returns the adjusted query.
	public func preSortScripts(_ preSortScripts: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: self.preSortScripts + preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Adds the indicated pre-find scripts and returns the adjusted query.
	public func preFindScripts(_ preFindScripts: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: self.preFindScripts + preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Adds the indicated post-find scripts and returns the adjusted query.
	public func postFindScripts(_ postFindScripts: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: self.postFindScripts + postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Sets the response layout and returns the adjusted query.
	public func responseLayout(_ responseLayout: String) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Adds response fields and returns the adjusted query.
	public func responseFields(_ responseFields: [String]) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: self.responseFields + responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Sets the maximum records to fetch and returns the adjusted query.
	public func maxRecords(_ maxRecords: Int) -> FMPQuery {
		return FMPQuery(queryFields: queryFields, sortFields: sortFields, recordId: recordId,
		                preSortScripts: preSortScripts, preFindScripts: preFindScripts,
		                postFindScripts: postFindScripts, responseLayout: responseLayout,
		                responseFields: responseFields, maxRecords: maxRecords, skipRecords: skipRecords,
		                action: action, database: database, layout: layout)
	}
	/// Sets the number of records to skip in the found set and returns the adjusted query.
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
		return "-db=\(database.fmpEscaped)&-lay=\(layout.fmpEscaped)&"
	}
	
	var sortFieldsString: String {
		var colNum = 1
		return sortFields.map { field -> String in
			let ret = "-sortfield.\(colNum)=\(field.name.fmpEscaped)&-sortorder.\(colNum)=\(field.order)"
			colNum += 1
			return ret
		}.joined(separator: "&")
	}
	
	var responseFieldsString: String {
		return responseFields.map { "-field=\($0.fmpEscaped)" }.joined(separator: "&")
	}
	
	var scriptsString: String {
		let preSorts = preSortScripts.map { "-script.presort=\($0.fmpEscaped)" }.joined(separator: "&")
		let preFinds = preFindScripts.map { "-script.prefind=\($0.fmpEscaped)" }.joined(separator: "&")
		let postFinds = postFindScripts.map { "-script=\($0.fmpEscaped)" }.joined(separator: "&")
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
		return "-lay.response=\(responseLayout.fmpEscaped)"
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
		return "-query=\(segments.joined(separator: ";").fmpEscaped)"
	}
	
	var compoundFieldsString: String {
		var num = 0
		var segments = [String]()
		for group in queryFields {
			let str = group.fields.map {
				num += 1
				// valueWithOp already encodes its value portion internally
				// and deliberately leaves the operator token unencoded —
				// do not re-encode the whole thing here.
				return "-q\(num)=\($0.name.fmpEscaped)&-q\(num).value=\($0.valueWithOp)"
			}.joined(separator: "&")
			segments.append(str)
		}
		return segments.joined(separator: "&")
	}
	
	public var description: String {
		return queryString
	}
	/// Returns the formulated query string.
	/// Useful for debugging purposes.
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
