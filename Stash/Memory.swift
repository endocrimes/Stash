//
//  Memory.swift
//  Stash
//
//  Created by  Danielle Lancashireon 21/08/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

import Foundation

public typealias MemoryCacheBlock = (cache: Memory) -> ()
public typealias MemoryCacheObjectBlock = (cache: Memory, key: String, object: NSCoding?) -> ()

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
    
    public var removeAllObjectsOnMemoryWarning: Bool = true
    
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.memory.async", DISPATCH_QUEUE_CONCURRENT)
    private let semaphore: dispatch_semaphore_t = dispatch_semaphore_create(1)
    
    private var objects: [String : NSCoding] = [String : NSCoding]()
    private var dates: [String : NSDate] = [String : NSDate]()
    private var costs: [String : Int] = [String : Int]()
    private var observationToken: NSObjectProtocol?
    
    public init() {
        observationToken = NSNotificationCenter.defaultCenter()
            .addObserverForName(UIApplicationDidReceiveMemoryWarningNotification,
                object: nil,
                queue: NSOperationQueue(),
                usingBlock: { [weak self] notification in
                    guard let strongSelf = self else { return }
                    if strongSelf.removeAllObjectsOnMemoryWarning {
                        strongSelf.removeAllObjects()
                    }
                })
    }
    
    deinit {
        guard let token = observationToken else { return }
        NSNotificationCenter.defaultCenter().removeObserver(token)
    }
    
    // MARK - Synchronous Methods
    
    public func setObject(object: NSCoding?, forKey: String, cost: Int = 0) {
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
    
    public func objectForKey(key: String) -> NSCoding? {
        let now = NSDate()
        
        var object: NSCoding?
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
        lock()
        let dates = self.dates.lazy
        unlock()
        
        dates
            .filter({ key, value -> Bool in
                return date.compare(value) == .OrderedDescending
            })
            .forEach { key, value in
                removeObjectForKey(key)
            }
    }
    
    public func trimToCost(cost: Int) {
        if self.totalCost < cost {
            return
        }
        
        lock()
        let orderedKeys = ((costs as NSDictionary).keysSortedByValueUsingSelector("compare:") as? [String])?.reverse() ?? []
        unlock()
        
        var totalCost: Int = self.totalCost
        
        for key in orderedKeys {
            removeObjectForKey(key)
            
            totalCost = self.totalCost
            if totalCost < cost {
                break
            }
        }
    }
    
    public func trimToCostByDate(cost: Int) {
        var totalCost = self.totalCost
        if totalCost <= cost {
            return
        }
        
        lock()
        let orderedKeys = (dates as NSDictionary).keysSortedByValueUsingSelector("compare:") as? [String]
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
    
    public func enumerateObjects(block: (key: String, value: NSCoding) -> ()) {
        lock()
        if let sortedKeys = (self.dates as NSDictionary).keysSortedByValueUsingSelector("compare:") as? [String] {
            for key in sortedKeys {
                guard let value = self.objects[key] else { return }
                
                block(key: key, value: value)
            }
        }
        unlock()
    }
    
    subscript(index: String) -> NSCoding? {
        get {
            return objectForKey(index)
        }
        set(newValue) {
            setObject(newValue, forKey: index)
        }
    }
    
    // MARK - Asynchronous Methods
    
    public func setObject(object: NSCoding?, forKey: String, cost: Int = 0, completionHandler: MemoryCacheBlock?) {
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
    
    public func enumerateObjects(block: (key: String, value: NSCoding) -> (), completionHandler: MemoryCacheBlock?) {
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
