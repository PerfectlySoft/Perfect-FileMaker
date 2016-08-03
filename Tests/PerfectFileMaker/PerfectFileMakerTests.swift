import XCTest
@testable import PerfectFileMaker

let testHost = "127.0.0.1"
let testPort = 80
let testUserName = ""
let testPassword = ""
let sampleDB = "FMServer_Sample"

class PerfectFileMakerTests: XCTestCase {
	
    func testDatabaseNames() {
		let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
		let expect = self.expectation(description: "done")
		
		fms.databaseNames {
			list in
			defer {
				expect.fulfill()
			}
			guard case .resultSet(let recordsArray) = list else {
				return XCTAssert(false, "\(list))")
			}
			for record in recordsArray {
				XCTAssert(record["DATABASE_NAME"] != nil)
			}
		}
		self.waitForExpectations(timeout: 5.0) {
			_ in
			
		}
    }
	
	func testLayoutNames() {
		let fms = FileMakerServer(host: testHost, port: 80, userName: testUserName, password: testPassword)
		let expect = self.expectation(description: "done")
		
		fms.layoutNames(database: sampleDB) {
			list in
			defer {
				expect.fulfill()
			}
			guard case .resultSet(let recordsArray) = list else {
				return XCTAssert(false, "\(list))")
			}
			for record in recordsArray {
				XCTAssert(record["LAYOUT_NAME"] != nil, "\(record)")
			}
		}
		self.waitForExpectations(timeout: 5.0) {
			_ in
			
		}
	}
	
	func testLayoutInfo() {
		let fms = FileMakerServer(host: testHost, port: 80, userName: testUserName, password: testPassword)
		let expect = self.expectation(description: "done")
		
		fms.layoutNames(database: sampleDB) {
			list in
			guard case .resultSet(let recordsArray) = list else {
				return XCTAssert(false, "\(list))")
			}
			for record in recordsArray {
				XCTAssert(record["LAYOUT_NAME"] != nil, "\(record)")
				fms.layoutInfo(database: sampleDB, layout: record["LAYOUT_NAME"]!) {
					result in
					guard case .layoutInfo(let layoutInfo) = result else {
						return XCTAssert(false, "\(list))")
					}
					defer {
						expect.fulfill()
					}
					for _ in layoutInfo.fields {
						//...
					}
				}
				break
			}
		}
		self.waitForExpectations(timeout: 5.0) {
			_ in
			
		}
	}

	func testEnumAllTheThings() {
		let expect = self.expectation(description: "done")
		let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
		
		fms.databaseNames {
			list in
			guard case .resultSet(let recordsArray) = list else {
				XCTAssert(false, "\(list))")
				return expect.fulfill()
			}
			var dbNames = recordsArray.map { $0["DATABASE_NAME"]! }.makeIterator()
			
			func layouts() {
				guard let dbName = dbNames.next() else {
					expect.fulfill()
					return
				}
				fms.layoutNames(database: dbName) {
					list in
					guard case .resultSet(let recordsArray) = list else {
						return
					}
					var layoutNames = recordsArray.map { $0["LAYOUT_NAME"]! }.makeIterator()
					
					func fields() {
						guard let layoutName = layoutNames.next() else {
							return layouts()
						}
						guard !layoutName.isEmpty else {
							return fields()
						}
						fms.layoutInfo(database: dbName, layout: layoutName) {
							result in
							guard case .layoutInfo(let layoutInfo) = result else {
								return fields()
							}
							for field in layoutInfo.fields {
								print("Field: \"\(dbName)\" \"\(layoutName)\" \(field)")
							}
							for (listName, valueList) in layoutInfo.valueLists {
								print("Value list: \"\(listName)\" \(valueList)")
							}
							fields()
						}
					}
					fields()
				}
			}
			layouts()
		}
		self.waitForExpectations(timeout: 60.0) {
			_ in
			
		}
	}
	
	func testQueryFindAll() {
		let query = FMPQuery(database: sampleDB, layout: "Task Details", action: .findAll)
		let expect = self.expectation(description: "done")
		let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
		
		fms.query(query) {
			result in
			
			expect.fulfill()
		}
		
		self.waitForExpectations(timeout: 60.0) {
			_ in
			
		}
	}
	
    static var allTests : [(String, (PerfectFileMakerTests) -> () throws -> Void)] {
		return [
			("testDatabaseNames", testDatabaseNames),
			("testLayoutNames", testLayoutNames),
			("testLayoutInfo", testLayoutInfo),
        ]
    }
}
