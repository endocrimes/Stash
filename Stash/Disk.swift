//
//  Disk.swift
//  Stash
//
//  Created by Danielle Lancashire on 21/08/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

import Foundation
#if os(iOS)
import UIKit
#endif

public typealias DiskCacheBlock = (cache: Disk) -> ()
public typealias DiskCacheObjectBlock = (cache: Disk, key: String, object: NSCoding?) -> ()

/**
 * The errors that can be thrown during the use of a Disk cache
 */
public enum DiskCacheErrors : ErrorType {
    case CacheURLCreationError(String)
    case FailedToCreateCacheDirectory
}

/**
 * `Disk` is a threadsafe key/value store backed by the local filesystem. It can
 * store and retreive any object that conforms to the `NSCoding` protocol - This
 * includes most Foundation classes including collection types, and also some
 * UIKit classes such as `UIImage`. Archiving is done by `NSKeyedArchiver`, which
 * is great for things like `UIImage` because it retains metadata, and skips
 * `UIImagePNGRepresentation()`.
 *
 * Unless explicitly noted, all properties and methods are safe to call from any
 * thread at any time.
 */
public final class Disk {
    private var state = DiskPrivateState()
    private let semaphore: dispatch_semaphore_t = dispatch_semaphore_create(1)
    private let concurrentQueue: dispatch_queue_t = dispatch_queue_create("com.rocketapps.stash.disk", DISPATCH_QUEUE_CONCURRENT)
    
    /// The maximum size of the cache on disk, use nil for infinite.
    public var maximumDiskSize: Double? {
        get {
            lock()
            let value = state.maximumSizeInBytes
            unlock()
            
            return value
        }
        set {
            lock()
            state.maximumSizeInBytes = newValue
            unlock()
        }
    }
    
    /// The current on-disk size of the cache in Bytes.
    public private(set) var byteCount: Double {
        get {
            lock()
            let value = state.byteCount
            unlock()
            
            return value
        }
        set {
            lock()
            state.byteCount = newValue
            unlock()
        }
    }
    
    /// The name of the cache
    public var name: String
    
    /**
     * Create a new instance of `Disk` with a given name and root storage path.
     * Only one `Disk` instance can exist for a given `name` and `rootPath`
     * at a time to avoid conflicts.
     *
     * parameter name:     The name of the cache.
     * parameter rootPath: The root cache directory.
     *
     * throws: see `DiskCacheErrors`
     *
     * returns: A new instance of Disk.
     */
    init(name: String, rootPath: String) throws {
        self.name = name
        guard let cacheURL = DiskCacheURL(withName: name, rootPath: rootPath) else {
            throw DiskCacheErrors.CacheURLCreationError("Disk failed to create a cache url with name: \(name), rootPath: \(rootPath)")
        }
        state.cacheURL = cacheURL
        
        // MARK - Setup Cache's directory
        
        try CreateCachesDirectoryAtURL(cacheURL)
		try setupDiskProperties()
    }
    
    // MARK - Synchronous Methods
    
    /**
     * Retreive the fileURL for a given key. This exists primarily for debugging
     * and you probably shouldn't need it under normal operation.
     */
    public func fileURLForKey(key: String) -> NSURL? {
        let now = NSDate()
        var fileURL: NSURL?
        let fileManager = NSFileManager.defaultManager()
        
        lock()
        fileURL = encodedFileURLForKey(key)
        
        if let url = fileURL, path = url.path where fileManager.fileExistsAtPath(path) {
            setFileModificationDate(now, forURL: url)
        }
        else {
            fileURL = nil
        }
        unlock()
        
        return fileURL
    }
    
    /**
     * Synchronously set an object for a given key. The calling thread will be 
     * blocked until safe access to the disk is available.
     *
     * parameter object: The object to store in the cache.
     * parameter forKey: A key to associate with the object.
     */
    public func setObject(object: NSCoding?, forKey: String) {
        if let data = object {
            let now = NSDate()
            let task = DiskBackgroundTask.start()
            
            lock()
            guard let fileURL = encodedFileURLForKey(forKey), let path = fileURL.path else { unlock(); return }
            
            if NSKeyedArchiver.archiveRootObject(data, toFile: path) {
                setFileModificationDate(now, forURL: fileURL)
                
                let values = try? fileURL.resourceValuesForKeys([ NSURLTotalFileAllocatedSizeKey ])
                if let diskFileSize = values?[NSURLTotalFileAllocatedSizeKey] as? Double {
                    state.sizes[forKey] = diskFileSize
                    state.byteCount += diskFileSize
                }
                
                if let limit = state.maximumSizeInBytes where state.byteCount > limit {
                    trimToSizeByDate(limit, completionHandler: nil)
                }
            }
            
            unlock()
            
            task.end()
        }
        else {
            removeObjectForKey(forKey)
        }
    }
    
    /**
     * Retreive an object from the cache. The calling thread will be blocked
     * until safe access to the disk is available.
     *
     * parameter key: The key associated with the value you wish to retreive.
     *
     * returns: The object associated with the key, or nil.
     */
    public func objectForKey(key: String) -> NSCoding? {
        let now = NSDate()
        let fileManager = NSFileManager.defaultManager()
        var object: NSCoding?
        lock()
        if let fileURL = encodedFileURLForKey(key), let path = fileURL.path where fileManager.fileExistsAtPath(path) {
            object = NSKeyedUnarchiver.unarchiveObjectWithFile(path) as? NSCoding
            setFileModificationDate(now, forURL: fileURL)
        }
        unlock()
        
        return object
    }
    
    /**
     * Remove the object associated with the given key. This method is safe to be
     * called for non-existing keys. The calling thread will be blocked until
     * safe access to the disk is available.
     *
     * parameter key: The key to remove the object for.
     */
    public func removeObjectForKey(key: String) {
        lock()
        _removeObjectForKey(key)
        unlock()
    }
    
    /**
     * Removes all the objects in the cache that have not been accessed before
     * the `date`. The calling thread will be blocked until file access is
     * available.
     */
    public func trimBeforeDate(date: NSDate) {
        lock()
        let dates = state.dates.lazy
        dates
            .filter({ key, value -> Bool in
                return date.compare(value) == .OrderedDescending
            })
            .forEach { key, value in
                _removeObjectForKey(key)
            }
        unlock()
    }
    
    /**
     * Trims the cache to a given size, removing the least-recently-used objects
     * first. The calling thread will be blocked until file access is available.
     *
     * parameter size: The size to trim the cache to.
     */
    public func trimToSizeByDate(size: Double) {
        var total = byteCount
        if total <= size {
            return
        }
        
        lock()
        let orderedKeys = state.dates.keysSortedByValues { $0.compare($1) == .OrderedAscending }
        for key in orderedKeys {
            _removeObjectForKey(key)
            
            total = state.byteCount
            if total <= size {
                break
            }
        }
        unlock()
    }
    
    /**
     * Remove all the objects from the cache. The calling thread will be blocked
     * until file access is available.
     */
    public func removeAllObjects() {
        lock()
        let keys = state.dates.keys
        keys.forEach(_removeObjectForKey)
        unlock()
    }
    
    /**
     * Get/Set objects in the cache for a given key.
     * The calling thread will be blocked until file access is available.
     */
    subscript(key: String) -> NSCoding? {
        get {
            return objectForKey(key)
        }
        set(newValue) {
            setObject(newValue, forKey: key)
        }
    }
    
    // MARK - Asynchronous Methods
    
    public func setObject(object: NSCoding?, forKey: String, completionHandler: DiskCacheBlock?) {
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
    
    public func trimToSizeByDate(size: Double, completionHandler: DiskCacheBlock?) {
        async { [weak self] in
            guard let strongSelf = self else { return }
            
            strongSelf.trimToSizeByDate(size)
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
    
    // MARK - Private Filesystem Functions
    
    private func setupDiskProperties() throws {
        let fileManager = NSFileManager.defaultManager()
        let keys = [
            NSURLContentModificationDateKey,
            NSURLTotalFileAllocatedSizeKey
        ]
        
        let allFiles = try fileManager.contentsOfDirectoryAtURL(state.cacheURL,
            includingPropertiesForKeys: keys,
            options: .SkipsHiddenFiles)
        
        allFiles.forEach { url in
            let key = keyForEncodedFileURL(url)!
            
            guard let metaDictionary = try? url.resourceValuesForKeys(keys) else {
                return
            }
            
            if let date = metaDictionary[NSURLContentModificationDateKey] as? NSDate {
                state.dates[key] = date
            }
            
            if let fileSize = metaDictionary[NSURLTotalFileAllocatedSizeKey] as? Double where fileSize > 0 {
                state.sizes[key] = fileSize
                state.byteCount += fileSize
            }
        }
    }
    
    private func setFileModificationDate(date: NSDate, forURL url: NSURL) -> Bool {
        guard let path = url.path, key = keyForEncodedFileURL(url) else { return false }
        do {
            try NSFileManager.defaultManager().setAttributes([ NSFileModificationDate : date ], ofItemAtPath: path)
        }
        catch {
            return false
        }
        
        state.dates[key] = date
        
        return true
    }
    
    // MARK - Private Key Helpers
    
    private func keyForEncodedFileURL(fileURL: NSURL) -> String? {
        guard let fileName = fileURL.lastPathComponent else {
            return nil
        }
        
        return decodedString(fileName)
    }
    
    private func encodedFileURLForKey(key: String) -> NSURL? {
        guard !key.characters.isEmpty, let encodedKey = encodedString(key) else { return nil }
        
        return state.cacheURL.URLByAppendingPathComponent(encodedKey)
    }
    
    private func decodedString(string: String) -> String? {
        guard !string.characters.isEmpty else { return nil }

        return string.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.alphanumericCharacterSet())
    }
    
    private func encodedString(string: String) -> String? {
        guard !string.characters.isEmpty else { return nil }
        
        return string.stringByRemovingPercentEncoding
    }
    
    private func _removeObjectForKey(key: String) {
        // TODO: Explore performance gains for a trash to do asynchronous deletes.
        let fileManager = NSFileManager.defaultManager()
        if let fileURL = encodedFileURLForKey(key) {
            let _ = try? fileManager.removeItemAtURL(fileURL)
            state.byteCount -= state.sizes[key] ?? 0
            state.dates.removeValueForKey(key)
            state.sizes.removeValueForKey(key)
        }
    }
}

public extension Disk {
    public var description: String {
        return "co.rocketapps.stash.disk.\(name)"
    }
}

private func DiskCacheURL(withName name: String, rootPath: String, prefix: String = "co.rocketapps.stash.disk") -> NSURL? {
    return NSURL.fileURLWithPathComponents([rootPath, name, prefix])
}

private func CreateCachesDirectoryAtURL(url: NSURL) throws -> Bool {
    let fileManager = NSFileManager.defaultManager()
    guard fileManager.fileExistsAtPath(url.absoluteString) == false else {
        return false
    }
    
    do {
        try fileManager.createDirectoryAtURL(url, withIntermediateDirectories: true, attributes: nil)
    }
    catch {
        throw DiskCacheErrors.FailedToCreateCacheDirectory
    }
    
    return true
}

private struct DiskPrivateState {
    var maximumSizeInBytes: Double? = nil
    var byteCount: Double = 0
    var dates: [String : NSDate] = [:]
    var sizes: [String : Double] = [:]
    var cacheURL: NSURL!
}

#if os(iOS)
private struct DiskBackgroundTask {
    var taskIdentifier: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    static func start() -> DiskBackgroundTask {
        var task = DiskBackgroundTask()
        task.taskIdentifier = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler {
            let taskIdentifier = task.taskIdentifier
            task.taskIdentifier = UIBackgroundTaskInvalid
            UIApplication.sharedApplication().endBackgroundTask(taskIdentifier)
        }
    
        return task
    }
    
    func end() {
        let taskIdentifier = self.taskIdentifier
        UIApplication.sharedApplication().endBackgroundTask(taskIdentifier)
    }
}
#else
private struct DiskBackgroundTask {
    static func start() -> DiskBackgroundTask { return DiskBackgroundTask() }
    func end() {}
}
#endif
