//
//  Memory.swift
//  Stash
//
//  Created by  Danielle Lancashireon 21/08/2015.
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
            lock()
            cost = state.maximumCost
            unlock()
            
            return cost
        }
        
        set {
            lock()
            state.maximumCost = newValue
            unlock()
            
            guard let newValue = newValue else { return }
            trimToCostByDate(newValue)
        }
    }
    
    public var totalCost: Int {
        get {
            var cost = 0
            lock()
            cost = state.totalCost
            unlock()
            
            return cost
        }
        
        set {
            lock()
            state.totalCost = newValue
            unlock()
        }
    }
    
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.memory.async", DISPATCH_QUEUE_CONCURRENT)
    private let semaphore: dispatch_semaphore_t = dispatch_semaphore_create(1)
    
    private var objects: [String : NSData] = [String : NSData]()
    private var dates: [String : NSDate] = [String : NSDate]()
    private var costs: [String : Int] = [String : Int]()
    
    init() {
    }
    
    // MARK - Synchronous Methods
    
    public func setObject(object: NSData?, forKey: String, cost: Int = 0) {
        guard let _ = object else {
            removeObjectForKey(forKey)
            return
        }
        
        let now = NSDate()
        
        let totalCost = self.totalCost
        let maximumCost = self.maximumCost
        let newCost = totalCost + cost
        
        lock()
        objects[forKey] = object
        dates[forKey] = now
        costs[forKey] = cost
        state.totalCost = newCost
        unlock()
        
        if let maximumCost = maximumCost {
            trimToCostByDate(maximumCost)
        }
    }
    
    public func objectForKey(key: String) -> NSData? {
        let now = NSDate()
        
        var object: NSData?
        lock()
        object = objects[key]
        unlock()
        
        if let _ = object {
            updateAccessTimeOfObjectForKey(key, date: now)
        }
        
        return object
    }
    
    public func removeObjectForKey(key: String) {
        lock()
        let cost = self.costs[key]
        if let cost = cost {
            state.totalCost -= cost
        }
        
        objects[key] = nil
        dates[key] = nil
        costs[key] = nil
        unlock()
    }
    
    public func trimBeforeDate(date: NSDate) {
        fatalError("Unimplemented Function")
    }
    
    public func trimToCost(cost: Int) {
        fatalError("Unimplemented Function")
    }
    
    public func trimToCostByDate(cost: Int) {
        var totalCost = self.totalCost
        if totalCost <= cost {
            return
        }
        
        var orderedKeys: [String]?
        lock()
        orderedKeys = (dates as NSDictionary).keysSortedByValueUsingSelector("compare:") as? [String]
        unlock()
        
        guard let keys: [String] = orderedKeys else { return }
        for key in keys {
            removeObjectForKey(key)
            
            totalCost = self.totalCost
            if totalCost <= cost {
                break
            }
        }
    }
    
    public func removeAllObjects() {
        lock()
        objects.removeAll()
        dates.removeAll()
        costs.removeAll()
        state.totalCost = 0
        unlock()
    }
    
    public func enumerateObjects(block: (key: String, value: NSData) -> ()) {
        lock()
        if let sortedKeys = (self.dates as NSDictionary).keysSortedByValueUsingSelector("compare:") as? [String] {
            for key in sortedKeys {
                guard let value = self.objects[key] else { return }
                
                block(key: key, value: value)
            }
        }
        unlock()
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
        lock()
        dates[key] = date
        unlock()
    }
    
    private func async(block: dispatch_block_t) {
        dispatch_async(concurrentQueue, block)
    }
    
    private func lock() {
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    }
    
    private func unlock() {
        dispatch_semaphore_signal(semaphore)
    }
}
