
import PerfectLib
import PerfectXML
import PerfectCURL
import cURL

public enum FMSGrammar: String {
	case fmResultSet = "fmresultset"
	case fmpXMLLayout = "FMPXMLLAYOUT"
	case fmpXMLResult = "FMPXMLRESULT"
}

public struct FMPLayoutField {
	public let name: String
	public let type: String
	public let valueList: String?
}

public struct FMPValueListItem {
	public let display: String
	public let value: String
}

public struct FMPLayoutInfo {
	public let fields: [FMPLayoutField]
	public let valueLists: [String:[FMPValueListItem]]
}

public enum FMSResult {
	case error(Int, String)
	case resultSet([[String:String]])
	case layoutInfo(FMPLayoutInfo)
}

public enum FMPAction {
	case find, findAll, findAny
	case new, edit, delete, duplicate
	case scripts
}

public enum FMPSortOrder {
	case ascending, descending, custom
}

public enum FMPLogicalOp {
	case and, or, not
}

public enum FMPFieldOp {
	case equal, contains, beginsWith, endsWith, greaterThan, greaterThanEqual, lessThan, lessThanEqual, notEqual
}

public struct FMPQueryField {
	public let name: String
	public let value: Any
	public let op: FMPFieldOp
	
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

public struct FMPQuery {
	let queryFields: [FMPQueryFieldGroup]
	let sortFields: [FMPSortField]
	
}

private let fmrs = "fmrs"
private let fmrsNamespaces = [(fmrs, "http://www.filemaker.com/xml/fmresultset")]
private let fmrsErrorCode = "/\(fmrs):fmresultset/\(fmrs):error/@code"
private let fmrsResultSet = "/\(fmrs):fmresultset/\(fmrs):resultset"
private let fmrsRecord = "\(fmrs):record"
private let fmrsField = "\(fmrs):field"
private let fmrsData = "\(fmrs):data/text()"

private let fmpxl = "fmpxl"
private let fmpxlNamespaces = [(fmpxl, "http://www.filemaker.com/fmpxmllayout")]
private let fmpxlErrorCode = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):ERRORCODE/text()"
private let fmpxlField = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):LAYOUT/\(fmpxl):FIELD"
private let fmpxlStyle = "\(fmpxl):STYLE"
private let fmpxlValueLists = "/\(fmpxl):FMPXMLLAYOUT/\(fmpxl):VALUELISTS/\(fmpxl):VALUELIST"
private let fmpxlValue = "\(fmpxl):VALUE"

public struct FileMakerServer {
	let host: String
	let port: Int
	let userName: String
	let password: String
	
	func makeUrl(query: String, grammar: FMSGrammar) -> String {
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
	
	func performRequest(query: String, grammar: FMSGrammar, callback: (FMSResult) -> ()) {
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
			case .fmResultSet: self.processGrammar_FMResultSet(doc: doc, callback: callback)
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
	
	func processGrammar_FMResultSet(doc: XDocument, callback: (FMSResult) -> ()) {
		let errorCode = checkError(doc: doc, xpath: fmrsErrorCode, namespaces: fmrsNamespaces)
		guard errorCode == 0 else {
			return callback(.error(errorCode, "Error from FileMaker server"))
		}
		guard let resultSet = doc.extractOne(path: fmrsResultSet, namespaces: fmrsNamespaces) else {
			return callback(.error(500, "Bad response"))
		}
		let recordsArray = self.pullRecords(resultSet: resultSet)
		callback(.resultSet(recordsArray))
	}
	
	func processGrammar_FMPXMLLayout(doc: XDocument, callback: (FMSResult) -> ()) {
		let errorCode = checkError(doc: doc, xpath: fmpxlErrorCode, namespaces: fmpxlNamespaces)
		guard errorCode == 0 else {
			return callback(.error(errorCode, "Error from FileMaker server"))
		}
		guard case .nodeSet(let fieldList) = doc.extract(path: fmpxlField, namespaces: fmpxlNamespaces) else {
			return callback(.error(500, "Bad response"))
		}
		
		var fields = [FMPLayoutField]()
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
			fields.append(FMPLayoutField(name: name, type: type, valueList: valueList.isEmpty ? nil : valueList))
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
	
	func processGrammar_FMPXMLResult(doc: XDocument, callback: (FMSResult) -> ()) {
		
	}
	
	public func databaseNames(completion: (FMSResult) -> ()) {
		performRequest(query: "-dbnames", grammar: .fmResultSet, callback: completion)
	}
	
	public func layoutNames(database: String, completion: (FMSResult) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-layoutnames", grammar: .fmResultSet, callback: completion)
	}
	
	public func layoutInfo(database: String, layout: String, completion: (FMSResult) -> ()) {
		performRequest(query: "-db=\(database.stringByEncodingURL)&-lay=\(layout.stringByEncodingURL)&-view", grammar: .fmpXMLLayout, callback: completion)
	}
}

