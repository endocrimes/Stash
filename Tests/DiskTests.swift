//
//  DiskTests.swift
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

class DiskTests: XCTestCase {
    var sut: Disk!
    
    // MARK - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first!
        let testDirectory = (documentsDirectory as NSString).stringByAppendingPathComponent("Tests")
        let fileManager = NSFileManager.defaultManager()

        // We don't care about errors for these.
        let _ = try? fileManager.removeItemAtPath(testDirectory)
        let _ = try? fileManager.createDirectoryAtPath(testDirectory, withIntermediateDirectories: true, attributes: nil)
        
        sut = try! Disk(name: "Test", rootPath: testDirectory)
    }
    
    override func tearDown() {
        sut = nil
        
        super.tearDown()
    }
    
    // MARK - Synchronous Tests
    
    func test_cannot_cache_object_with_empty_key() {
        let testData = dummyData("Hello, World")
        let testKey = ""
        
        sut[testKey] = testData
        
        let object = sut[testKey] as? NSData
        
        XCTAssertEqual(object, nil)
    }
    
    func test_can_write_data_to_cache_sync() {
        let testData = dummyData("Hello, World")
        let testKey = "test_can_write_data_to_cache_sync"
        
        sut.setObject(testData, forKey: testKey)
        
        let object = sut.objectForKey(testKey) as? NSData
        
        XCTAssertEqual(object, testData)
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
        
        let object = sut.objectForKey(testKey) as? NSData
        
        XCTAssertEqual(object, testObject)
        
        sut.removeObjectForKey(testKey)
        
        let hopefullyNilObject = sut.objectForKey(testKey)
        
        XCTAssertNil(hopefullyNilObject)
    }
    
    func test_remove_object_for_unset_key_sync() {
        let notPresentKey = "test_remove_object_for_unset_key_sync"
        let storeKey = "test_remove_object_for_unset_key_sync2"
        let testObject = dummyData("Hi")
        sut.setObject(testObject, forKey: storeKey)
        
        let count = sut.byteCount
        sut.removeObjectForKey(notPresentKey)
        XCTAssertEqual(sut.byteCount, count)
    }
    
    func test_can_read_and_write_data_using_subscript() {
        let testKey = "test_can_read_and_write_data_using_subscript"
        let testObject = dummyData("Hello!")
        
        sut[testKey] = testObject
        
        let object = sut[testKey] as? NSData
        
        XCTAssertEqual(object, testObject)
    }
    
    func test_setting_nil_data_removes_object_for_key_sync() {
        let testKey = "test_setting_nil_data_removes_object_for_key_sync"
        let testObject = dummyData("Hi")
        
        sut.setObject(testObject, forKey: testKey)
        
        let object = sut.objectForKey(testKey) as? NSData
        
        XCTAssertEqual(object, testObject)
        
        sut.setObject(nil, forKey: testKey)
        
        let hopefullyNilObject = sut.objectForKey(testKey)
        
        XCTAssertNil(hopefullyNilObject)
    }
    
    func test_can_trim_to_size_by_date_sync() {
        struct TestObject {
            let key: String = NSUUID().UUIDString
            let value: NSData
            
            init(size: Int) {
                let data = malloc(size)
                value = NSData(bytes: data, length: size)
            }
        }
        
        let objects = [
            TestObject(size: 100),
            TestObject(size: 100),
            TestObject(size: 100),
            TestObject(size: 100),
            TestObject(size: 100)
        ]
        
        for object in objects {
            sut.setObject(object.value, forKey: object.key)
        }
        
        sut.trimToSizeByDate(100)
        
        let firstObjectKey = objects.first!.key
        
        XCTAssertNil(sut[firstObjectKey])
    }
    
    func test_can_remove_all_objects_sync() {
        let kvPairs = [
            "key1" : dummyData("Hi"),
            "key2" : dummyData("Hello"),
            "key3" : dummyData("Hello, World")
        ]
        
        for (key, value) in kvPairs {
            sut[key] = value
            
            XCTAssertEqual(sut[key] as? NSData, value)
        }
        
        sut.removeAllObjects()
        
        for (key, _) in kvPairs {
            let object = sut[key]
            XCTAssertNil(object)
        }
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
            XCTAssertEqual(value as? NSData, testData)
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
        
        let object = sut.objectForKey(testKey) as? NSData
        
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
        
        let object = sut.objectForKey(testKey) as? NSData
        
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
            
            XCTAssertEqual(value, sut[key] as? NSData)
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
}
