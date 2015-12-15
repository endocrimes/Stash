Pod::Spec.new do |s|
  s.name = "Stash"
  s.version = "0.3.0"
  s.summary = "A parallel object cache for Swift 2.0"
  s.description = <<-DESC
                   Stash is a key/value store for temporarily persisting objects, such as network responses (images etc), or expensive to reproduce values.
                   `Stash` is a simple object that wraps `Memory` (a fast in memory store) and `Disk` (a slower, file system backed store).
                   `Memory` will automatically clear itself when your app receives a memory warning.
                   `Disk` will persist items until you manually remove items, or automatically using limits.
                   The caches will accept any object that conforms to `NSCoding`, although I'm open to considering a different encoding.
                   The caches primary API's are synchronous, although there are asynchronous wrappers around most of them.
                   DESC
  s.homepage = "https://github.com/endocrimes/Stash"
  s.license = { :type => "MIT", :file => "LICENSE" }
  s.author = { "Danielle Lancashire" => "Dan@Tomlinson.io" }
  s.social_media_url = "http://twitter.com/endocrimes"
  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.9"
  s.watchos.deployment_target = "2.0"
  s.tvos.deployment_target = "9.0"
  s.source = { :git => "https://github.com/endocrimes/Stash.git", :tag => s.version }
  s.source_files  = "Source", "Stash/*.swift"
end
