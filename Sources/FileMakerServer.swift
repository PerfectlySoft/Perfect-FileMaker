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

extension XNode {
	var childElements: [XElement] {
		return self.childNodes.flatMap { $0 as? XElement }
	}
}

public enum FMPGrammar: String {
	case fmResultSet = "fmresultset"
//	case fmpXMLLayout = "FMPXMLLAYOUT"

}

let fmpxl = "fmpxl"
let fmpxlNamespaces = [(fmpxl, "http://www.filemaker.com/fmpxmllayout")]
let fmpxlErrorCode = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):ERRORCODE/text()"
let fmpxlField = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):LAYOUT/\(fmpxl):FIELD"
let fmpxlStyle = "\(fmpxl):STYLE"
let fmpxlValueLists = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):VALUELISTS/\(fmpxl):VALUELIST"
let fmpxlValue = "\(fmpxl):VALUE"

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
	
	func makeUrl(grammar: FMPGrammar) -> String {
		let scheme = port == 443 ? "https" : "http"
		let url = "\(scheme)://\(host):\(port)/fmi/xml/\(grammar.rawValue).xml"
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
	
	func checkError(doc: XDocument, xpath: String, namespaces: [(String, String)]) -> Int {
		guard let errorNode = doc.extractOne(path: xpath, namespaces: namespaces),
			let nodeValue = errorNode.nodeValue,
			let errorCode = Int(nodeValue) else {
				return 500
		}
		return errorCode
	}
	
	func performRequest(query: String, grammar: FMPGrammar, callback: @escaping (FMPResult) -> ()) {
		let curl = makeCURL(url: makeUrl(grammar: grammar))
				
		let byteArray = [UInt8](query.utf8)
		curl.setOption(CURLOPT_POST, int: 1)
		curl.setOption(CURLOPT_POSTFIELDSIZE, int: byteArray.count)
		curl.setOption(CURLOPT_COPYPOSTFIELDS, v: UnsafeMutablePointer(mutating: byteArray))
		curl.setOption(CURLOPT_HTTPHEADER, s: "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" )
		
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
			case .fmResultSet: self.processGrammar_FMPResultSet(doc: doc, callback: callback)
			}
		}
	}
	
	func processGrammar_FMPResultSet(doc: XDocument, callback: (FMPResult) -> ()) {
		let errorCode = checkError(doc: doc, xpath: fmrsErrorCode, namespaces: fmrsNamespaces)
		guard errorCode == 0 else {
			return callback(.error(errorCode, "Error from FileMaker server"))
		}
		guard let result = FMPResultSet(doc: doc) else {
			return callback(.error(500, "Invalid response from FileMaker server"))
		}
		callback(.resultSet(result))
	}
	
	public func databaseNames(completion: @escaping (FMPResult) -> ()) {
		performRequest(query: "-dbnames", grammar: .fmResultSet, callback: completion)
	}
	
	public func layoutNames(database: String, completion: @escaping (FMPResult) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-layoutnames", grammar: .fmResultSet, callback: completion)
	}
	
	public func layoutInfo(database: String, layout: String, completion: @escaping (FMPResult) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-lay=\(layout.stringByEncodingURL)&-view", grammar: .fmResultSet) {
			result in
			guard case .resultSet(let set) = result else {
				return completion(result)
			}
			return completion(.layoutInfo(set.layoutInfo))
		}
	}
	
	public func query(_ query: FMPQuery, skipValueLists: Bool = false, completion: @escaping (FMPResult) -> ()) {
		let queryString = query.queryString
		performRequest(query: queryString, grammar: .fmResultSet, callback: completion)
	}
}

