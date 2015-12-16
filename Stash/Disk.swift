//
//  Disk.swift
//  Stash
//
//  Created by Daniel Tomlinson on 21/08/2015.
//  Copyright © 2015 Rocket Apps. All rights reserved.
//

import Foundation

public typealias DiskCacheBlock = (cache: Disk) -> ()
public typealias DiskCacheObjectBlock = (cache: Disk, key: String, object: NSCoding?) -> ()

public enum DiskCacheErrors : ErrorType {
    case CacheURLCreationError(String)
    case FailedToCreateCacheDirectory
}

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
    
    public var byteCount: Double {
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
    
    public var name: String
    
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
    
    public func removeObjectForKey(key: String) {
        // TODO: Explore performance gains for a trash to do asynchronous deletes.
        let fileManager = NSFileManager.defaultManager()
        lock()
        if let fileURL = encodedFileURLForKey(key) {
            let _ = try? fileManager.removeItemAtURL(fileURL)
            state.byteCount -= state.sizes[key] ?? 0
            state.dates.removeValueForKey(key)
            state.sizes.removeValueForKey(key)
        }
        unlock()
    }
    
    public func trimBeforeDate(date: NSDate) {
        lock()
        let dates = state.dates.lazy
        unlock()
        
        dates
            .filter({ key, value -> Bool in
                return date.compare(value) == .OrderedDescending
            })
            .forEach { key, value in
                removeObjectForKey(key)
            }
    }
    
    public func trimToSizeByDate(size: Double) {
        var total = byteCount
        if total <= size {
            return
        }
        
        lock()
        let orderedKeys = state.dates.keysSortedByValues { $0.compare($1) == .OrderedAscending }
        unlock()
        
        for key in orderedKeys {
            removeObjectForKey(key)
            
            total = byteCount
            if total <= size {
                break
            }
        }
    }
    
    public func removeAllObjects() {
        lock()
        let keys = state.dates.keys
        unlock()
        
        for key in keys {
            removeObjectForKey(key)
        }
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

#if os(ios) || os(watchos)
private struct DiskBackgroundTask {
    var taskIdentifier: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    static func start() -> DiskBackgroundTask {
        var task = DiskBackgroundTask()
        task.taskIdentifier = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler {
            let taskIdentifier = task.taskIdentifier
            task.taskIdentifier = nil
            UIApplication.sharedApplication().endBackgroundTask(taskIdentifier)
        }
    
        return task
    }
    
    func end() {
        let taskIdentifier = self.taskIdentifier
        self.taskIdentifier = nil
        UIApplication.sharedApplication().endBackgroundTask(taskIdentifier)
    }
}
#else
private struct DiskBackgroundTask {
    static func start() -> DiskBackgroundTask { return DiskBackgroundTask() }
    func end() {}
}
#endif
