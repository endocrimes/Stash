//
//  Memory.swift
//  Stash
//
//  Created by Daniel Tomlinson on 21/08/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

import Foundation

public typealias MemoryCacheBlock = (cache: Memory) -> ()
public typealias MemoryCacheObjectBlock = (cache: Memory, key: String, object: NSData?) -> ()


public class Memory {
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.memory", DISPATCH_QUEUE_CONCURRENT)
    
    private var objects: [String : NSData] = [String : NSData]()
    private var dates: [String : NSDate] = [String : NSDate]()
    private var costs: [String : Int] = [String : Int]()
    
    init() {
    }
    
    // MARK - Synchronous Methods
    
    public func setObject(object: NSData?, forKey: String, cost: Int = 0) {
        if let _ = object {
            
        }
        else {
            removeObjectForKey(forKey)
        }
    }
    
    public func objectForKey(key: String) -> NSData? {
        return nil
    }
    
    public func removeObjectForKey(key: String) {
    }
    
    public func trimBeforeDate(date: NSDate) {
    }
    
    public func removeAllObjects() {
    }
    
    subscript(index: String) -> NSData? {
        get {
            return objectForKey(index)
        }
        set(newValue) {
            setObject(newValue, forKey: index)
        }
    }
    
    // MARK - Asynchronous Methods
    
    public func setObject(object: NSData?, forKey: String, cost: Int = 0, completionHandler: MemoryCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf[forKey] = object
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func objectForKey(key: String, completionHandler: MemoryCacheObjectBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            let object = strongSelf[key]
            completionHandler?(cache: strongSelf, key: key, object: object)
        }
    }
    
    public func removeObjectForKey(key: String, completionHandler: MemoryCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.removeObjectForKey(key)
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func trimBeforeDate(date: NSDate, completionHandler: MemoryCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.trimBeforeDate(date)
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func removeAllObjects(completionHandler: MemoryCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.removeAllObjects()
            completionHandler?(cache: strongSelf)
        }
    }
    
    // MARK - Private Methods
    
    private func async(block: dispatch_block_t) {
        dispatch_async(concurrentQueue, block)
    }
}
