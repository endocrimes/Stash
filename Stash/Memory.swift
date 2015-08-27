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
            self.lock()
            let cost = state.maximumCost
            self.unlock()
            
            return cost
        }
        
        set {
            self.lock()
            state.maximumCost = newValue
            self.unlock()
        }
    }
    
    public var totalCost: Int {
        get {
            self.lock()
            let cost = state.totalCost
            self.unlock()
            
            return cost
        }
        
        set {
            self.lock()
            state.totalCost = newValue
            self.unlock()
        }
    }
    
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.memory", DISPATCH_QUEUE_CONCURRENT)
    private let semaphore: dispatch_semaphore_t = dispatch_semaphore_create(1)
    
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
            
            self.lock()
            objects[forKey] = object
            dates[forKey] = now
            costs[forKey] = cost
            state.totalCost = newCost
            self.unlock()
        }
        else {
            removeObjectForKey(forKey)
        }
    }
    
    public func objectForKey(key: String) -> NSData? {
        let now = NSDate()
        
        self.lock()
        let object = objects[key]
        self.unlock()
        
        if let _ = object {
            updateAccessTimeOfObjectForKey(key, date: now)
        }
        
        return object
    }
    
    public func removeObjectForKey(key: String) {
        lock()
        let cost = costs[key]
        if let cost = cost {
            state.totalCost -= cost
        }
        
        objects[key] = nil
        dates[key] = nil
        costs[key] = nil
        unlock()
    }
    
    public func trimBeforeDate(date: NSDate) {
        
    }
    
    public func trimToCost(cost: Int) {
        
    }
    
    public func trimToCostByDate(cost: Int) {
        
    }
    
    public func removeAllObjects() {
        lock()
        objects.removeAll()
        dates.removeAll()
        costs.removeAll()
        state.totalCost = 0
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
    
    // MARK - Private Methods
    
    /**
    This method updates the last access time of an object at a given key.
    It assumes that an object for the given key exists.
    */
    private func updateAccessTimeOfObjectForKey(key: String, date: NSDate) {
        self.lock()
        dates[key] = date
        self.unlock()
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
