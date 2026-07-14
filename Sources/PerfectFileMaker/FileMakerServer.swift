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

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PerfectXML

extension XNode {
	var childElements: [XElement] {
		self.childNodes.compactMap { $0 as? XElement }
	}
}

// Only the "fmresultset" grammar (find/new/edit/delete results) is
// implemented — the FMPXMLLAYOUT grammar (full layout/value-list/picklist
// introspection) was never wired up in the original library either (its
// XPath constants existed but nothing referenced them, and neither the
// README nor the tests mention it). Deliberately not building it out
// during this modernization pass: doing so with zero real-server corpus
// to validate correctness against would be speculative feature
// completion, not a port. Revisit only if a real need appears.
enum FMPGrammar: String {
	case fmResultSet = "fmresultset"
}

public enum FMPError: Error {
	/// An error code and message.
	case serverError(Int, String)
}

/// A connection to a FileMaker Server instance.
public struct FileMakerServer: Sendable {
	let host: String
	let port: Int
	let userName: String
	let password: String
	/// `nil` (the default) infers `https` only when `port == 443`,
	/// matching this library's original behavior — real deployments
	/// sometimes run FileMaker Server's classic XML Web Publishing over
	/// plain HTTP on a trusted internal network, so this isn't hard-
	/// blocked. Set explicitly to make the choice observable rather than
	/// relying on a magic port number; see `effectiveUseTLS`.
	let useTLS: Bool?
	let urlSession: URLSession

	/// Initialize using a host, port, username and password.
	/// `urlSession` defaults to `.shared`; inject a session configured
	/// with a `URLProtocol` mock for testing (matching this ecosystem's
	/// established pattern in `Perfect-AuthNet`/`Perfect-FileMaker-DataAPI`).
	public init(
		host: String, port: Int, userName: String, password: String,
		useTLS: Bool? = nil, urlSession: URLSession = .shared
	) {
		self.host = host
		self.port = port
		self.userName = userName
		self.password = password
		self.useTLS = useTLS
		self.urlSession = urlSession
	}

	var effectiveUseTLS: Bool {
		useTLS ?? (port == 443)
	}

	func makeURL(grammar: FMPGrammar) -> URL? {
		let scheme = effectiveUseTLS ? "https" : "http"
		return URL(string: "\(scheme)://\(host):\(port)/fmi/xml/\(grammar.rawValue).xml")
	}

	func makeRequest(url: URL) -> URLRequest {
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
		if !userName.isEmpty {
			if !effectiveUseTLS {
				// Not a hard failure — some deployments genuinely run
				// FileMaker Server's classic XML Web Publishing over
				// plain HTTP on a trusted internal network — but
				// transiting Basic-Auth credentials in cleartext should
				// never be silent.
				FileHandle.standardError.write(Data(
					"PerfectFileMaker: sending credentials to \(url.absoluteString) over plain HTTP (useTLS not set and port != 443).\n".utf8
				))
			}
			let credentials = Data("\(userName):\(password)".utf8).base64EncodedString()
			request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
		}
		return request
	}

	func checkError(doc: XDocument, xpath: String, namespaces: [(String, String)]) -> Int {
		guard let errorNode = doc.extractOne(path: xpath, namespaces: namespaces),
			let nodeValue = errorNode.nodeValue,
			let errorCode = Int(nodeValue) else {
				return 500
		}
		return errorCode
	}

	func performRequest(query: String, grammar: FMPGrammar) async throws -> FMPResultSet {
		guard let url = makeURL(grammar: grammar) else {
			throw FMPError.serverError(500, "Invalid FileMaker Server URL")
		}
		var request = makeRequest(url: url)
		request.httpBody = Data(query.utf8)

		let (body, response) = try await urlSession.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
			throw FMPError.serverError(statusCode, "Bad response")
		}
		guard let bodyString = String(data: body, encoding: .utf8),
			let doc = XDocument(fromSource: bodyString) else {
			throw FMPError.serverError(500, "Bad response")
		}
		switch grammar {
		case .fmResultSet:
			return try processGrammar_FMPResultSet(doc: doc)
		}
	}

	func processGrammar_FMPResultSet(doc: XDocument) throws -> FMPResultSet {
		let errorCode = checkError(doc: doc, xpath: fmrsErrorCode, namespaces: fmrsNamespaces)
		guard errorCode == 0 || errorCode == 200 else {
			throw FMPError.serverError(errorCode, "Error from FileMaker server")
		}
		guard let result = FMPResultSet(doc: doc) else {
			throw FMPError.serverError(500, "Invalid response from FileMaker server")
		}
		return result
	}

	func names(from result: FMPResultSet, key: String) -> [String] {
		var names = [String]()
		for rec in result.records {
			guard let field = rec.elements[key],
				case .field(_, let value) = field else {
					continue
			}
			names.append("\(value)")
		}
		return names
	}

	/// Retrieve the list of databases hosted by the server.
	public func databaseNames() async throws -> [String] {
		let result = try await performRequest(query: "-dbnames", grammar: .fmResultSet)
		return names(from: result, key: "DATABASE_NAME")
	}

	/// Retrieve the list of layouts for a particular database.
	public func layoutNames(database: String) async throws -> [String] {
		let result = try await performRequest(query: "-db=\(database.fmpEscaped)&-layoutnames", grammar: .fmResultSet)
		return names(from: result, key: "LAYOUT_NAME")
	}

	/// Get a database's layout information. Includes all field and portal names.
	public func layoutInfo(database: String, layout: String) async throws -> FMPLayoutInfo {
		let result = try await performRequest(
			query: "-db=\(database.fmpEscaped)&-lay=\(layout.fmpEscaped)&-view",
			grammar: .fmResultSet
		)
		return result.layoutInfo
	}

	/// Perform a query and return the resulting data.
	public func query(_ query: FMPQuery) async throws -> FMPResultSet {
		try await performRequest(query: query.queryString, grammar: .fmResultSet)
	}
}
