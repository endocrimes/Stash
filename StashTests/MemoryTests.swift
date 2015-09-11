//
//  MemoryTests.swift
//  Stash
//
//  Created by Daniel Tomlinson on 21/08/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

import XCTest
@testable import Stash

private func dummyData(string: String) -> NSData {
    return string.dataUsingEncoding(NSUTF8StringEncoding)!
}

class MemoryTests: XCTestCase {
    var sut: Memory!
    
    // MARK - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        
        sut = Memory()
    }
    
    override func tearDown() {
        sut = nil
        
        super.tearDown()
    }
    
    // MARK - Synchronous Tests
    
    func test_can_write_data_to_cache_sync() {
        let testData = dummyData("Hello, World")
        let testKey = "test_can_write_data_to_cache_sync"
        
        sut.setObject(testData, forKey: testKey)
        
        let object = sut.objectForKey(testKey)
        
        XCTAssertEqual(testData, object)
    }
    
    func test_can_read_nil_value_for_unset_key_sync() {
        let testKey = "test_can_read_nil_value_for_unset_key_sync"
        
        let object = sut.objectForKey(testKey)
        
        XCTAssertNil(object)
    }
    
    func test_can_remove_object_for_key_sync() {
        let testKey = "test_can_remove_object_for_key_sync"
        let testObject = dummyData("Hi")
        
        sut.setObject(testObject, forKey: testKey)
        
        let object = sut.objectForKey(testKey)
        
        XCTAssertEqual(object, testObject)
        
        sut.removeObjectForKey(testKey)
        
        let hopefullyNilObject = sut.objectForKey(testKey)
        
        XCTAssertNil(hopefullyNilObject)
    }
    
    func test_can_read_and_write_data_using_subscript() {
        let testKey = "test_can_read_and_write_data_using_subscript"
        let testObject = dummyData("Hello!")
        
        sut[testKey] = testObject
        
        let object = sut[testKey]
        
        XCTAssertEqual(testObject, object)
    }
    
    func test_setting_nil_data_removes_object_for_key_sync() {
        let testKey = "test_setting_nil_data_removes_object_for_key_sync"
        let testObject = dummyData("Hi")
        
        sut.setObject(testObject, forKey: testKey)
        
        let object = sut.objectForKey(testKey)
        
        XCTAssertEqual(object, testObject)
        
        sut.setObject(nil, forKey: testKey)
        
        let hopefullyNilObject = sut.objectForKey(testKey)
        
        XCTAssertNil(hopefullyNilObject)
    }
    
    func test_inserting_object_updates_total_cost_sync() {
        let testKey = "test_inserting_object_updates_total_cost_sync"
        let testObject = dummyData("Hi")
        let testCost = 10
        
        sut.setObject(testObject, forKey: testKey, cost: testCost)
        
        XCTAssertEqual(sut.totalCost, testCost)
    }
    
    func test_removing_object_updates_total_cost_sync() {
        let testKey = "test_removing_object_updates_total_cost_sync"
        let testObject = dummyData("Hi")
        let testCost = 10
        
        sut.setObject(testObject, forKey: testKey, cost: testCost)
        
        sut.removeObjectForKey(testKey)
        
        XCTAssertEqual(sut.totalCost, 0)
    }
    
    func test_can_remove_all_objects_sync() {
        let kvPairs = [
            "key1" : dummyData("Hi"),
            "key2" : dummyData("Hello"),
            "key3" : dummyData("Hello, World")
        ]
        
        for (key, value) in kvPairs {
            sut[key] = value
            
            XCTAssertEqual(value, sut[key])
        }
        
        sut.removeAllObjects()
        
        for (key, _) in kvPairs {
            let object = sut[key]
            XCTAssertNil(object)
        }
    }
    
    func test_can_enumerate_over_objects_sync() {
        let kvPairs = [
            "key1" : dummyData("Hi"),
            "key2" : dummyData("Hello"),
            "key3" : dummyData("Hello, World")
        ]
        
        for (key, value) in kvPairs {
            sut[key] = value
            
            XCTAssertEqual(value, sut[key])
        }
        
        let expectedCount = kvPairs.count
        var count = 0
        sut.enumerateObjects { _ in
            count++
        }
        
        XCTAssertEqual(count, expectedCount)
    }
    
    func test_can_trim_to_cost_by_date_sync() {
        struct TestObject {
            let key: String = NSUUID().UUIDString
            let value: NSData = NSUUID().UUIDString.dataUsingEncoding(NSUTF8StringEncoding)!
            let cost: Int
        }
        
        let objects = [
            TestObject(cost: 100),
            TestObject(cost: 100),
            TestObject(cost: 100),
            TestObject(cost: 100),
            TestObject(cost: 100)
        ]
        
        for object in objects {
            sut.setObject(object.value, forKey: object.key, cost: object.cost)
        }
        
        sut.trimToCostByDate(400)
        
        let firstObjectKey = objects.first!.key
        
        XCTAssertNil(sut[firstObjectKey])
    }
    
    // MARK - Asynchronous Tests
    
    func test_can_write_data_to_cache_async() {
        let testData = dummyData("Hello, World")
        let testKey = "test_can_write_data_to_cache_async"
        
        let setExpectation = expectationWithDescription("Write data expectation")
        sut.setObject(testData, forKey: testKey, completionHandler: { _ in
            setExpectation.fulfill()
        })
        
        waitForExpectationsWithTimeout(1.0, handler: nil)
        
        let readExpectation = expectationWithDescription("Read data expectation")
        
        sut.objectForKey(testKey, completionHandler: { _, _, value in
            XCTAssertEqual(value, testData)
            readExpectation.fulfill()
        })
        
        waitForExpectationsWithTimeout(1.0, handler: nil)
    }
    
    func test_can_read_nil_value_for_unset_key_async() {
        let testKey = "test_can_read_nil_value_for_unset_key_async"
        
        let readExpectation = expectationWithDescription("Read data expectation")
        sut.objectForKey(testKey, completionHandler: { _, _, value in
            XCTAssertNil(value)
            readExpectation.fulfill()
        })
        
        waitForExpectationsWithTimeout(1.0, handler: nil)
    }
    
    func test_can_remove_object_for_key_async() {
        let testKey = "test_can_remove_object_for_key_async"
        let testObject = dummyData("Hi")
        
        sut.setObject(testObject, forKey: testKey)
        
        let object = sut.objectForKey(testKey)
        
        XCTAssertEqual(object, testObject)
        
        let removeExpectation = expectationWithDescription("Remove object expectation")
        sut.removeObjectForKey(testKey, completionHandler: { _ in
            removeExpectation.fulfill()
        })
        
        waitForExpectationsWithTimeout(1.0, handler: nil)
        
        let hopefullyNilObject = sut.objectForKey(testKey)
        
        XCTAssertNil(hopefullyNilObject)
    }
    
    func test_setting_nil_data_removes_object_for_key_async() {
        let testKey = "test_setting_nil_data_removes_object_for_key_async"
        let testObject = dummyData("Hi")
        
        sut.setObject(testObject, forKey: testKey)
        
        let object = sut.objectForKey(testKey)
        
        XCTAssertEqual(object, testObject)
        
        let setExpectation = expectationWithDescription("Set object expectation")
        sut.setObject(nil, forKey: testKey, completionHandler: { _ in
            setExpectation.fulfill()
        })
        
        waitForExpectationsWithTimeout(1.0, handler: nil)
        
        let hopefullyNilObject = sut.objectForKey(testKey)
        
        XCTAssertNil(hopefullyNilObject)
    }
    
    func test_can_remove_all_objects_async() {
        let kvPairs = [
            "key1" : dummyData("Hi"),
            "key2" : dummyData("Hello"),
            "key3" : dummyData("Hello, World")
        ]
        
        for (key, value) in kvPairs {
            sut[key] = value
            
            XCTAssertEqual(value, sut[key])
        }
        
        let removeExpectation = expectationWithDescription("Remove all objects expectation")
        sut.removeAllObjects { _ in
            removeExpectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(1.0, handler: nil)
        
        for (key, _) in kvPairs {
            let object = sut[key]
            XCTAssertNil(object)
        }
    }
    
    func test_can_enumerate_over_objects_async() {
        let kvPairs = [
            "key1" : dummyData("Hi"),
            "key2" : dummyData("Hello"),
            "key3" : dummyData("Hello, World")
        ]
        
        for (key, value) in kvPairs {
            sut[key] = value
            
            XCTAssertEqual(value, sut[key])
        }
        
        let expectedCount = kvPairs.count
        var count = 0
        let enumeratorBlock: (String, NSData) -> () = { _ in
            count++
        }
        
        let expectation = expectationWithDescription("Completion handler called")
        
        sut.enumerateObjects(enumeratorBlock) { _ in
            expectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(0.1, handler: nil)
        
        XCTAssertEqual(count, expectedCount)
    }
}
