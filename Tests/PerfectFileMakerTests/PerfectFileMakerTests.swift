import XCTest
@testable import PerfectFileMaker

let testHost = "127.0.0.1"
let testPort = 80
let testUserName = ""
let testPassword = ""
let sampleDB = "FMServer_Sample"

class PerfectFileMakerTests: XCTestCase {
	
	func testQueryFindAll() {
		let query = FMPQuery(database: sampleDB, layout: "Task Details", action: .findAll)
		let expect = self.expectation(description: "done")
		let fms = FileMakerServer(host: testHost, port: testPort, userName: testUserName, password: testPassword)
		
		fms.query(query) {
			result in
			defer {
				expect.fulfill()
			}
			guard case .resultSet(let resultSet) = result else {
				return XCTAssert(false, "\(result))")
			}
			let fields = recordsArray.layoutInfo.fields
			let recordCount = recordsArray.records.count
			XCTAssert(recordCount > 0)
			for i in 0..<recordCount {
				let rec = recordsArray.records[i]
				for field in fields {
					XCTAssert(rec[field.name] != nil)
				}
			}
		}
		
		self.waitForExpectations(timeout: 60.0) {
			_ in
			
		}
	}
	
    static var allTests : [(String, (PerfectFileMakerTests) -> () throws -> Void)] {
		return [
			("testQueryFindAll", testQueryFindAll),
        ]
    }
}
