//
//  Stash.swift
//  Stash
//
//  Created by  Danielle Lancashireon 21/08/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

import Foundation

public typealias CacheBlock = (cache: Stash) -> ()
public typealias CacheObjectBlock = (cache: Stash, key: String, object: NSCoding?) -> ()

/**
 * Stash is a thread safe key/value store for persisting temporary objects and
 * data that is expensive to reproduce (i.e downloaded images, or computationally
 * expensive results.
 *
 * Stash itself is incredibly lightweight, and simply wraps a fast memory cache
 * and a slower disk-based cache. If objects are removed from the memory cache
 * through events such as recieving a memory warning, they remain in the disk
 * cache, and will be added into the memory cache when next retreived.
 *
 * Stash was influenced by TMCache and PINCache.
 */
public final class Stash {
    
    /// The underlying memory cache. See `Memory` for more.
    public let memoryCache: Memory
    
    /// The underlying disk cache. See `Disk` for more.
    public let diskCache: Disk!
    
    /// The name of the cache. Used to create the `diskCache`.
    public let name: String
    
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash", DISPATCH_QUEUE_CONCURRENT)
    
   /**
    * Create a new instance of `Stash` with a given `name` and `rootPath`.
    *
    * Multiple instances of `Stash` with the same `name` are permitted and can
    * access the same data.
    *
    * :param: name     The name of the cache.
    * :param: rootPath The path of the cache on disk.
    */
    public init(name: String, rootPath: String) throws {
        self.name = name
        memoryCache = Memory()
        
        /*
            This is a hack around not being able to throw before properties are
            initialized. For now, making diskCache implicitly unwrapped, and
            adding this do/catch should be fine.
        */
        do {
            diskCache = try Disk(name: name, rootPath: rootPath)
        }
        catch let e {
            diskCache = nil
            throw e
        }
    }
    
    // MARK - Synchronous Methods
    
   /**
    * Stores an object in the cache for the specified key. This method blocks 
    * the calling thread until the object has been set.
    *
    * @param object An object to store in the cache.
    * @param key A key to associate with the object. This string will be copied.
    */
    public func setObject(object: NSCoding?, forKey: String) {
        guard let _ = object else { removeObjectForKey(forKey); return }
        memoryCache[forKey] = object
        diskCache[forKey] = object
    }
    
   /**
    * Retrieves the object for the specified key. This method blocks the calling 
    * thread until the object is available.
    *
    * :param: key The key associated with the object.
    */
    public func objectForKey(key: String) -> NSCoding? {
        if let object = memoryCache[key] {
            return object
        }
        else if let object = diskCache[key] {
            return object
        }
        
        return nil
    }
    
   /**
    * Removes the object for the specified key. This method blocks the calling
    * thread until the object has been removed.
    *
    * :param: key The key associated with the object to be removed.
    */
    public func removeObjectForKey(key: String) {
        memoryCache.removeObjectForKey(key)
        diskCache.removeObjectForKey(key)
    }
    
    /**
    * Removes all objects from the cache that have not been used since the 
    * specified date. This method blocks the calling thread until the cache has
    * been trimmed.
    *
    * :param: date Objects that haven't been accessed since this date are removed
    *   from the cache.
    */
    public func trimBeforeDate(date: NSDate) {
        memoryCache.trimBeforeDate(date)
        diskCache.trimBeforeDate(date)
    }
    
   /**
    * Removes all objects from the cache. This method blocks the calling thread 
    * until the cache has been cleared.
    */
    public func removeAllObjects() {
        memoryCache.removeAllObjects()
        diskCache.removeAllObjects()
    }
    
    public subscript(index: String) -> NSCoding? {
        get {
            return objectForKey(index)
        }
        set(newValue) {
            setObject(newValue, forKey: index)
        }
    }
    
    // MARK - Asynchronous Methods
    
    public func setObject(object: NSCoding?, forKey: String, completionHandler: CacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf[forKey] = object
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func objectForKey(key: String, completionHandler: CacheObjectBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            let object = strongSelf[key]
            completionHandler?(cache: strongSelf, key: key, object: object)
        }
    }
    
    public func removeObjectForKey(key: String, completionHandler: CacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.removeObjectForKey(key)
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func trimBeforeDate(date: NSDate, completionHandler: CacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.trimBeforeDate(date)
            completionHandler?(cache: strongSelf)
        }
    }
    
    public func removeAllObjects(completionHandler: CacheBlock?) {
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
