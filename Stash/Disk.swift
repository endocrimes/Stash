//
//  Disk.swift
//  Stash
//
//  Created by Daniel Tomlinson on 21/08/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

import Foundation

public typealias DiskCacheBlock = (cache: Disk) -> ()
public typealias DiskCacheObjectBlock = (cache: Disk, key: String, object: NSData?) -> ()

private struct DiskPrivateState {
    var maximumSizeInBytes: Double? = nil
    var byteCount: Double = 0
}

public final class Disk {
    private var state = DiskPrivateState()
    private let semaphore: dispatch_semaphore_t = dispatch_semaphore_create(1)
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.disk", DISPATCH_QUEUE_CONCURRENT)
    
    /// The maximum size of the cache on disk, use nil for infinite.
    public var maximumDiskSize: Double? {
        get {
            self.lock()
            let value = state.maximumSizeInBytes
            self.unlock()
            
            return value
        }
        set {
            self.lock()
            state.maximumSizeInBytes = newValue
            self.unlock()
        }
    }
    
    public var byteCount: Double {
        get {
            self.lock()
            let value = state.byteCount
            self.unlock()
            
            return value
        }
        set {
            self.lock()
            state.byteCount = newValue
            self.unlock()
        }
    }
    
    init(name: String, rootPath: String) {
    }
    
    // MARK - Synchronous Methods
    
    public func setObject(object: NSData?, forKey: String) {
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
    
    public func setObject(object: NSData?, forKey: String, completionHandler: DiskCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf[forKey] = object
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func objectForKey(key: String, completionHandler: DiskCacheObjectBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            let object = strongSelf[key]
            completionHandler?(cache: strongSelf, key: key, object: object)
        }
    }
    
    public func removeObjectForKey(key: String, completionHandler: DiskCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.removeObjectForKey(key)
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func trimBeforeDate(date: NSDate, completionHandler: DiskCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.trimBeforeDate(date)
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func removeAllObjects(completionHandler: DiskCacheBlock?) {
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
    
    private func lock() {
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    }
    
    private func unlock() {
        dispatch_semaphore_signal(semaphore)
    }
}
