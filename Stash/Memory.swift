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

private struct MemoryPrivateState {
    var maximumCost: Int? = nil
    var totalCost: Int = 0
}

public final class Memory {
    private var state = MemoryPrivateState()
    
    public var maximumCost: Int? {
        get {
            var cost: Int? = nil
            readBlockSync {
                cost = self.state.maximumCost
            }
            
            return cost
        }
        
        set {
            writeBlockSync {
                self.state.maximumCost = newValue
            }
        }
    }
    
    public var totalCost: Int {
        get {
            var cost = 0
            readBlockSync {
               cost = self.state.totalCost
            }
            
            return cost
        }
        
        set {
            writeBlockSync {
                self.state.totalCost = newValue
            }
        }
    }
    
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.memory.async", DISPATCH_QUEUE_CONCURRENT)
    private let syncQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.memory.internal", DISPATCH_QUEUE_CONCURRENT)
    
    private var objects: [String : NSData] = [String : NSData]()
    private var dates: [String : NSDate] = [String : NSDate]()
    private var costs: [String : Int] = [String : Int]()
    
    init() {
    }
    
    // MARK - Synchronous Methods
    
    public func setObject(object: NSData?, forKey: String, cost: Int = 0) {
        if let _ = object {
            let now = NSDate()
            
            let totalCost = self.totalCost
            let newCost = totalCost + cost
            
            writeBlockSync {
                self.objects[forKey] = object
                self.dates[forKey] = now
                self.costs[forKey] = cost
                self.state.totalCost = newCost
            }
        }
        else {
            removeObjectForKey(forKey)
        }
    }
    
    public func objectForKey(key: String) -> NSData? {
        let now = NSDate()
        
        var object: NSData?
        readBlockSync {
            object = self.objects[key]
        }
        
        if let _ = object {
            updateAccessTimeOfObjectForKey(key, date: now)
        }
        
        return object
    }
    
    public func removeObjectForKey(key: String) {
        writeBlockSync {
            let cost = self.costs[key]
            if let cost = cost {
                self.state.totalCost -= cost
            }
        
            self.objects[key] = nil
            self.dates[key] = nil
            self.costs[key] = nil
        }
    }
    
    public func trimBeforeDate(date: NSDate) {
        fatalError("Unimplemented Function")
    }
    
    public func trimToCost(cost: Int) {
        fatalError("Unimplemented Function")
    }
    
    public func trimToCostByDate(cost: Int) {
        fatalError("Unimplemented Function")
    }
    
    public func removeAllObjects() {
        writeBlockSync {
            self.objects.removeAll()
            self.dates.removeAll()
            self.costs.removeAll()
            self.state.totalCost = 0
        }
    }
    
    public func enumerateObjects(block: (key: String, value: NSData) -> ()) {
        readBlockSync {
            if let sortedKeys = (self.dates as NSDictionary).keysSortedByValueUsingSelector("compare:") as? [String] {
                for key in sortedKeys {
                    guard let value = self.objects[key] else { return }
                    
                    block(key: key, value: value)
                }
            }
        }
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
    
    public func enumerateObjects(block: (key: String, value: NSData) -> (), completionHandler: MemoryCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.enumerateObjects(block)
            completionHandler?(cache: strongSelf)
        }
    }

    // MARK - Private Methods
    
    /**
    This method updates the last access time of an object at a given key.
    It assumes that an object for the given key exists.
    */
    private func updateAccessTimeOfObjectForKey(key: String, date: NSDate) {
        writeBlockSync {
            self.dates[key] = date
        }
    }
    
    private func async(block: dispatch_block_t) {
        dispatch_async(concurrentQueue, block)
    }
    
    private func writeBlockSync(block: () -> ()) {
        dispatch_barrier_sync(syncQueue, block)
    }
    
    private func readBlockSync(block: () -> ()) {
        dispatch_sync(syncQueue, block)
    }
    
    private func writeBlockAsync(block: () -> ()) {
        dispatch_barrier_async(syncQueue, block)
    }
    
    private func readBlockAsync(block: () -> ()) {
        dispatch_async(syncQueue, block)
    }
}
