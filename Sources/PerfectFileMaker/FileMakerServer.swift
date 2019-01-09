//
//  FileMakerServer.swift
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
import PerfectXML
import PerfectCURL
import cURL

extension XNode {
	var childElements: [XElement] {
		#if swift(>=4.1)
			return self.childNodes.compactMap { $0 as? XElement }
		#else
			return self.childNodes.flatMap { $0 as? XElement }
		#endif
	}
}

enum FMPGrammar: String {
	case fmResultSet = "fmresultset"
	case fmResultSet = "FMPXMLRESULT" // This piece of data is case sensitive
}

let fmpxl = "fmpxl"
let fmpxlNamespaces = [(fmpxl, "http://www.filemaker.com/fmpxmllayout")]
let fmpxlErrorCode = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):ERRORCODE/text()"
let fmpxlField = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):LAYOUT/\(fmpxl):FIELD"
let fmpxlStyle = "\(fmpxl):STYLE"
let fmpxlValueLists = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):VALUELISTS/\(fmpxl):VALUELIST"
let fmpxlValue = "\(fmpxl):VALUE"

public enum FMPError: Error {
	/// An error code and message.
	case serverError(Int, String)
}

/// A connection to a FileMaker Server instance.
public struct FileMakerServer {
	let host: String
	let port: Int
	let userName: String
	let password: String
	
	/// Initialize using a host, port, username and password.
	public init(host: String, port: Int, userName: String, password: String) {
		self.host = host
		self.port = port
		self.userName = userName
		self.password = password
	}
	
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
	
	func performRequest(query: String, grammar: FMPGrammar, callback: @escaping (() throws -> FMPResultSet) -> ()) {
		let curl = makeCURL(url: makeUrl(grammar: grammar))
				
		let byteArray = [UInt8](query.utf8)
		curl.setOption(CURLOPT_POST, int: 1)
		curl.setOption(CURLOPT_POSTFIELDSIZE, int: byteArray.count)
		curl.setOption(CURLOPT_COPYPOSTFIELDS, v: UnsafeMutablePointer(mutating: byteArray))
		curl.setOption(CURLOPT_HTTPHEADER, s: "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" )
		
		curl.perform {
			code, header, body in
			guard curl.responseCode == 200 else {
				return callback({ throw FMPError.serverError(curl.responseCode, "Bad response") })
			}
			let bodyString = UTF8Encoding.encode(bytes: body)
			guard let doc = XDocument(fromSource: bodyString) else {
				return callback({ throw FMPError.serverError(500, "Bad response") })
			}
			switch grammar {
			case .fmResultSet: self.processGrammar_FMPResultSet(doc: doc, callback: callback)
			}
		}
	}
	
	func processGrammar_FMPResultSet(doc: XDocument, callback: (() throws -> FMPResultSet) -> ()) {
		let errorCode = checkError(doc: doc, xpath: fmrsErrorCode, namespaces: fmrsNamespaces)
		guard errorCode == 0 || errorCode == 200 else {
			return callback({ throw FMPError.serverError(errorCode, "Error from FileMaker server") })
		}
		guard let result = FMPResultSet(doc: doc) else {
			return callback({ throw FMPError.serverError(500, "Invalid response from FileMaker server") })
		}
		callback({ return result })
	}
	
	func setToNames(result: FMPResultSet, key: String, completion: @escaping (() throws -> [String]) -> ()) {
		var names = [String]()
		for rec in result.records {
			guard let field = rec.elements[key],
				case .field(_, let value) = field else {
					continue
			}
			names.append("\(value)")
		}
		return completion({ return names })
	}
	
	/// Retrieve the list of database hosted by the server.
	public func databaseNames(completion: @escaping (() throws -> [String]) -> ()) {
		performRequest(query: "-dbnames", grammar: .fmResultSet) {
			result in
			do {
				self.setToNames(result: try result(), key: "DATABASE_NAME", completion: completion)
			} catch let e {
				completion({ throw e })
			}
		}
	}

	/// Retrieve the list of layouts for a particular database.
	public func layoutNames(database: String, completion: @escaping (() throws -> [String]) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-layoutnames", grammar: .fmResultSet) {
			result in
			do {
				self.setToNames(result: try result(), key: "LAYOUT_NAME", completion: completion)
			} catch let e {
				completion({ throw e })
			}
		}
	}
	
	/// Get a database's layout information. Includes all field and portal names.
	public func layoutInfo(database: String,
	                       layout: String,
	                       completion: @escaping (() throws -> FMPLayoutInfo) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-lay=\(layout.stringByEncodingURL)&-view", grammar: .fmResultSet) {
			result in
			do {
				let layoutInfo = try result().layoutInfo
				return completion({ return layoutInfo })
			} catch let e {
				completion({ throw e })
			}
		}
	}
	
	/// Perform a query and provide any resulting data. 
	public func query(_ query: FMPQuery, completion: @escaping (() throws -> FMPResultSet) -> ()) {
		let queryString = query.queryString
		performRequest(query: queryString, grammar: .fmResultSet, callback: completion)
	}
	
	/// Perform the queries and provide the resulting data.
//	public func query(_ query: [FMPQuery], completion: @escaping (() throws -> FMPResultSet) -> ()) {
//		let queryString = query.queryString
//		performRequest(query: queryString, grammar: .fmResultSet, callback: completion)
//	}
}

