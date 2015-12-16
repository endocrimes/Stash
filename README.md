# Stash

![Travis Build Status](https://api.travis-ci.org/DanielTomlinson/Stash.svg)

Stash is a parallel object cache for Swift. It's based on [TMCache](https://github.com/Tumblr/TMCache).

Stash is a key/value store for temporarily persisting objects, such as network responses (images etc), or expensive to reproduce values.

`Stash` is a simple object that wraps `Memory` (a fast in memory store) and `Disk` (a slower, file system backed store).
`Memory` will automatically clear itself when your app receives a memory warning.
`Disk` will persist items until you manually remove items, or automatically using limits.

The caches will accept any object that conforms to `NSCoding`, although I'm open to considering a different encoding.

The caches primary API's are synchronous, although there are asynchronous wrappers around most of them.

## Usage

Stash provides a relatively simple sync API, that can be used like so:

```swift
let stash = try! Stash(name: "MyCache", rootPath: NSTemporaryDirectory())

let image = UIImage(...)
stash["MyKey"] = image

let retreivedImage = stash["MyKey"] as? UIImage
```

and an async API:

```swift
let stash = try! Stash(name: "MyCache", rootPath: NSTemporaryDirectory())

let image = UIImage(...)
stash.setObject(image, forKey: "MyKey") { cache: Stash in
    // It's Done!!!
}

// Some time later, to access
stash.objectForKey("MyKey") { cache, key, value in
    let image = value as? UIImage
}
```

## Installation

### CocoaPods

Add `pod Stash` to your Podfile, and run `pod install`

### Swift Package Manager

Add this repository to your Package.swift, and run `swift build`
