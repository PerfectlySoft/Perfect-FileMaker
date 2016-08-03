//
//  PostgreFileMaker.swift
//  PostgreFileMaker
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
import PerfectXML
import PerfectCURL
import cURL

public enum FMPGrammar: String {
	//	case fmResultSet = "fmresultset"
	case fmpXMLLayout = "FMPXMLLAYOUT"
	case fmpXMLResult = "FMPXMLRESULT"
}

let fmrs = "fmrs"
let fmrsNamespaces = [(fmrs, "http://www.filemaker.com/xml/fmresultset")]
let fmrsErrorCode = "/\(fmrs):fmresultset/\(fmrs):error/@code"
let fmrsResultSet = "/\(fmrs):fmresultset/\(fmrs):resultset"
let fmrsRecord = "\(fmrs):record"
let fmrsField = "\(fmrs):field"
let fmrsData = "\(fmrs):data/text()"

let fmpxl = "fmpxl"
let fmpxlNamespaces = [(fmpxl, "http://www.filemaker.com/fmpxmllayout")]
let fmpxlErrorCode = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):ERRORCODE/text()"
let fmpxlField = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):LAYOUT/\(fmpxl):FIELD"
let fmpxlStyle = "\(fmpxl):STYLE"
let fmpxlValueLists = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):VALUELISTS/\(fmpxl):VALUELIST"
let fmpxlValue = "\(fmpxl):VALUE"

let fmpxr = "fmpxr"
let fmpxrNamespaces = [(fmpxr, "http://www.filemaker.com/fmpxmlresult")]
let fmpxrErrorCode = "/\(fmpxr):FMPXMLRESULT/\(fmpxr):ERRORCODE/text()"
let fmpxrDatabase = "/\(fmpxr):FMPXMLRESULT/\(fmpxr):DATABASE"
let fmpxrField = "/\(fmpxr):FMPXMLRESULT/\(fmpxr):METADATA/\(fmpxr):FIELD"
let fmpxrRow = "/\(fmpxr):FMPXMLRESULT/\(fmpxr):RESULTSET/\(fmpxr):ROW"
let fmpxrCol = "\(fmpxr):COL"
let fmpxrData = "\(fmpxr):DATA"

public enum FMPResult {
	case error(Int, String)
	case resultSet(FMPResultSet)
	case layoutInfo(FMPLayoutInfo)
}

public struct FileMakerServer {
	let host: String
	let port: Int
	let userName: String
	let password: String
	
	func makeUrl(query: String, grammar: FMPGrammar) -> String {
		let scheme = port == 443 ? "https" : "http"
		let url = "\(scheme)://\(host):\(port)/fmi/xml/\(grammar.rawValue).xml?\(query)"
		return url
	}
	
	func makeCURL(url: String) -> CURL {
		let curl = CURL(url: url)
		if !userName.isEmpty {
			curl.setOption(CURLOPT_USERNAME, s: userName)
			curl.setOption(CURLOPT_PASSWORD, s: password)
		}
		return curl
	}
	
	func pullFields(fromRecord: XNode) -> [String:String] {
		var recordDict = [String:String]()
		guard case .nodeSet(let fields) = fromRecord.extract(path: fmrsField, namespaces: fmrsNamespaces) else {
			return recordDict
		}
		for field in fields {
			guard let fieldName = field.extractOne(path: "@name", namespaces: fmrsNamespaces)?.nodeValue else {
				continue
			}
			if let fieldData = field.extractOne(path: fmrsData, namespaces: fmrsNamespaces) as? XText,
				let nodeValue = fieldData.nodeValue {
					recordDict[fieldName] = nodeValue
			} else {
				recordDict[fieldName] = ""
			}
		}
		return recordDict
	}
	
	func pullRecords(resultSet: XNode) -> [[String:String]] {
		var recordsArray = [[String:String]]()
		guard case .nodeSet(let records) = resultSet.extract(path: fmrsRecord, namespaces: fmrsNamespaces) else {
			return recordsArray
		}
		for record in records {
			let recordDict = pullFields(fromRecord: record)
			recordsArray.append(recordDict)
		}
		return recordsArray
	}
	
	func performRequest(query: String, grammar: FMPGrammar, callback: (FMPResult) -> ()) {
		let curl = makeCURL(url: makeUrl(query: query, grammar: grammar))
		curl.perform {
			code, header, body in
			guard curl.responseCode == 200 else {
				return callback(.error(curl.responseCode, "Bad response"))
			}
			let bodyString = UTF8Encoding.encode(bytes: body)
			guard let doc = XDocument(fromSource: bodyString) else {
				return callback(.error(500, "Bad response"))
			}
			switch grammar {
			case .fmpXMLLayout: self.processGrammar_FMPXMLLayout(doc: doc, callback: callback)
			case .fmpXMLResult: self.processGrammar_FMPXMLResult(doc: doc, callback: callback)
//			case .fmResultSet: self.processGrammar_FMResultSet(doc: doc, callback: callback)
			}
		}
	}
	
	func checkError(doc: XDocument, xpath: String, namespaces: [(String, String)]) -> Int {
		guard let errorNode = doc.extractOne(path: xpath, namespaces: namespaces),
			let nodeValue = errorNode.nodeValue,
			let errorCode = Int(nodeValue) else {
				return 500
		}
		return errorCode
	}
	
//	func processGrammar_FMResultSet(doc: XDocument, callback: (FMPResult) -> ()) {
//		let errorCode = checkError(doc: doc, xpath: fmrsErrorCode, namespaces: fmrsNamespaces)
//		guard errorCode == 0 else {
//			return callback(.error(errorCode, "Error from FileMaker server"))
//		}
//		guard let resultSet = doc.extractOne(path: fmrsResultSet, namespaces: fmrsNamespaces) else {
//			return callback(.error(500, "Bad response"))
//		}
//		let recordsArray = self.pullRecords(resultSet: resultSet)
//		callback(.resultSet(recordsArray))
//	}
	
	func processGrammar_FMPXMLLayout(doc: XDocument, callback: (FMPResult) -> ()) {
		let errorCode = checkError(doc: doc, xpath: fmpxlErrorCode, namespaces: fmpxlNamespaces)
		guard errorCode == 0 else {
			return callback(.error(errorCode, "Error from FileMaker server"))
		}
		guard case .nodeSet(let fieldList) = doc.extract(path: fmpxlField, namespaces: fmpxlNamespaces) else {
			return callback(.error(500, "Bad response"))
		}
		
		var fields = [FMPFieldInfo]()
		for field in fieldList {
			guard let field = field as? XElement else {
				continue
			}
			guard let name = field.getAttribute(name: "NAME") else {
				continue
			}
			let style = field.extractOne(path: fmpxlStyle, namespaces: fmpxlNamespaces) as? XElement
			let type = style?.getAttribute(name: "TYPE") ?? ""
			let valueList = style?.getAttribute(name: "VALUELIST") ?? ""
			fields.append(FMPFieldInfo(name: name, type: type, valueList: valueList.isEmpty ? nil : valueList))
		}
		
		var valueLists = [String:[FMPValueListItem]]()
		if case .nodeSet(let valueListNodes) = doc.extract(path: fmpxlValueLists, namespaces: fmpxlNamespaces) {
			for node in valueListNodes {
				guard let node = node as? XElement else {
					continue
				}
				guard let name = node.getAttribute(name: "NAME") else {
					continue
				}
				guard case .nodeSet(let values) = node.extract(path: fmpxlValue, namespaces: fmpxlNamespaces), !values.isEmpty else {
					continue
				}
				var valueListItems = [FMPValueListItem]()
				for value in values {
					guard let value = value as? XElement else {
						continue
					}
					guard let display = value.getAttribute(name: "DISPLAY"),
						let nodeValue = value.nodeValue else {
							continue
					}
					valueListItems.append(FMPValueListItem(display: display, value: nodeValue))
				}
				valueLists[name] = valueListItems
			}
		}
		callback(.layoutInfo(FMPLayoutInfo(fields: fields, valueLists: valueLists)))
	}
	
	func processGrammar_FMPXMLResult(doc: XDocument, callback: (FMPResult) -> ()) {
		let errorCode = checkError(doc: doc, xpath: fmpxrErrorCode, namespaces: fmpxrNamespaces)
		guard errorCode == 0 else {
			return callback(.error(errorCode, "Error from FileMaker server"))
		}
		
	}
	
	public func databaseNames(completion: (FMPResult) -> ()) {
		performRequest(query: "-dbnames", grammar: .fmpXMLResult, callback: completion)
	}
	
	public func layoutNames(database: String, completion: (FMPResult) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-layoutnames", grammar: .fmpXMLResult, callback: completion)
	}
	
	public func layoutInfo(database: String, layout: String, completion: (FMPResult) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-lay=\(layout.stringByEncodingURL)&-view", grammar: .fmpXMLLayout, callback: completion)
	}
	
	public func query(_ query: FMPQuery, completion: (FMPResult) -> ()) {
		let queryString = query.queryString
		print(queryString)
		performRequest(query: queryString, grammar: .fmpXMLResult, callback: completion)
	}
}

