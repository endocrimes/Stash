# Stash

Stash is a parallel object cache for Swift. It's based on [TMCache](https://github.com/Tumblr/TMCache).

Stash is a key/value store for temporarily persisting objects, such as network responses (images etc), or expensive to reproduce values.

`Stash` is a simple object that wraps `Memory` (a fast in memory store) and `Disk` (a slower, file system backed store).
`Memory` will automatically clear itself when your app receives a memory warning.
`Disk` will persist items until you manually remove items, or automatically using limits.

The caches will accept any object that conforms to `NSCoding`, although I'm open to considering a different encoding.

The caches primary API's are synchronous, although there are asynchronous wrappers around most of them.
