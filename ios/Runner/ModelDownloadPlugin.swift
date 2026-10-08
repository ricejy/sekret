import CryptoKit
import Flutter
import Foundation

/// Only public catalogue weights use this session. Private data never enters it.
/// URLSession owns transfer execution while Flutter is suspended.
final class ModelDownloadPlugin: NSObject, FlutterPlugin, URLSessionDownloadDelegate {
  static let shared = ModelDownloadPlugin()
  static let identifier = "com.ricejy.sekret.reviewed-model-download"
  static let artifactHash = "9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9"
  static let artifactBytes: Int64 = 2_075_618_400
  static let artifactURL = URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q3_K_M.gguf")!
  static let hosts: Set<String> = ["huggingface.co", "cdn-lfs.huggingface.co", "cdn-lfs-us-1.huggingface.co", "cdn-lfs-eu-1.huggingface.co", "cas-bridge.xethub.hf.co", "us.aws.cdn.hf.co"]
  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("reviewed-models", isDirectory: true)
  }
  private var staged: URL { Self.directory.appendingPathComponent("download.partial") }
  private var current: URLSessionDownloadTask?
  private var received: Int64 = 0
  private var failed = false
  private var cancelling = false
  private var cancelWaiters: [FlutterResult] = []
  var backgroundCompletion: (() -> Void)?
  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.waitsForConnectivity = true
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCredentialStorage = nil
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForResource = 7 * 24 * 60 * 60
    return URLSession(configuration: config, delegate: self, delegateQueue: .main)
  }()

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.addMethodCallDelegate(shared, channel: FlutterMethodChannel(
      name: "com.ricejy.sekret/model_download", binaryMessenger: registrar.messenger()))
  }

  func reconnect() { _ = session }

  private func tasks(_ completion: @escaping ([URLSessionTask]) -> Void) {
    session.getAllTasks { tasks in DispatchQueue.main.async { completion(tasks) } }
  }

  private func adopt(_ tasks: [URLSessionTask]) {
    current = tasks.compactMap { $0 as? URLSessionDownloadTask }.first {
      $0.taskDescription == Self.artifactHash && $0.originalRequest?.url == Self.artifactURL
    }
    if let current { received = max(0, current.countOfBytesReceived) }
  }

  private func checkStorage() throws {
    let root = Self.directory
    guard root.standardizedFileURL == root.resolvingSymlinksInPath(),
      staged.standardizedFileURL == staged.resolvingSymlinksInPath() else {
      throw CocoaError(.fileWriteNoPermission)
    }
    if FileManager.default.fileExists(atPath: staged.path) {
      guard try staged.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        throw CocoaError(.fileWriteNoPermission)
      }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var protectedRoot = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try protectedRoot.setResourceValues(values)
    // Model weights are public. Chats/knowledge retain complete protection.
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
  }

  private func removeStaging() throws {
    try checkStorage()
    if FileManager.default.fileExists(atPath: staged.path) {
      try FileManager.default.removeItem(at: staged)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPending":
      tasks { tasks in
        self.adopt(tasks)
        result(self.current != nil || FileManager.default.fileExists(atPath: self.staged.path))
      }
    case "start":
      let args = call.arguments as? [String: Any] ?? [:]
      guard args["url"] as? String == Self.artifactURL.absoluteString,
        args["sha256"] as? String == Self.artifactHash,
        (args["bytes"] as? NSNumber)?.int64Value == Self.artifactBytes,
        args["destination"] as? String == staged.path, !cancelling else {
        result(error()); return
      }
      tasks { tasks in
        guard !self.cancelling else { result(self.error()); return }
        self.adopt(tasks)
        do {
          try self.checkStorage()
          if self.current == nil && !FileManager.default.fileExists(atPath: self.staged.path) {
            self.failed = false
            self.received = 0
            var request = URLRequest(url: Self.artifactURL)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let task = self.session.downloadTask(with: request)
            task.countOfBytesClientExpectsToReceive = Self.artifactBytes
            task.taskDescription = Self.artifactHash
            self.current = task
            task.resume()
          }
          result(nil)
        } catch { result(self.error()) }
      }
    case "status":
      if FileManager.default.fileExists(atPath: staged.path) && !cancelling {
        result(["phase": "complete", "bytes": Self.artifactBytes])
      } else {
        result(["phase": failed || current == nil ? "failed" : "downloading", "bytes": received])
      }
    case "cancel":
      cancelWaiters.append(result)
      guard !cancelling else { return }
      cancelling = true
      tasks { tasks in
        self.adopt(tasks)
        if tasks.isEmpty { self.finishCancellation() }
        else { tasks.forEach { $0.cancel() } }
      }
    case "hash":
      // Only the store's two fixed files; hashed off the main thread.
      let path = (call.arguments as? [String: Any])?["path"] as? String
      let installed = Self.directory.appendingPathComponent("\(Self.artifactHash).gguf")
      guard let path, path == staged.path || path == installed.path else {
        result(hashError()); return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let digest = Self.sha256(ofFileAt: URL(fileURLWithPath: path))
        DispatchQueue.main.async {
          guard let digest else { result(self.hashError()); return }
          result(["bytes": digest.bytes, "sha256": digest.hex])
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  /// Hardware-accelerated SHA-256 in 8 MB reads, so verifying ~2 GB takes
  /// seconds without holding the file in memory.
  static func sha256(ofFileAt url: URL) -> (bytes: Int64, hex: String)? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    var bytes: Int64 = 0
    while true {
      let chunk: Data?
      do {
        chunk = try autoreleasepool { try handle.read(upToCount: 8 << 20) }
      } catch { return nil }
      guard let chunk, !chunk.isEmpty else { break }
      hasher.update(data: chunk)
      bytes += Int64(chunk.count)
    }
    let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return (bytes, hex)
  }

  private func hashError() -> FlutterError {
    FlutterError(code: "model_hash_failed", message: "The model file could not be checked.", details: nil)
  }

  private func error() -> FlutterError {
    FlutterError(code: "model_download_failed", message: "The model transfer could not complete. Retry from Models.", details: nil)
  }

  private func finishCancellation() {
    current = nil
    received = 0
    failed = true
    var cleanupError: FlutterError?
    do { try removeStaging() } catch { cleanupError = self.error() }
    cancelling = false
    let waiters = cancelWaiters
    cancelWaiters.removeAll()
    waiters.forEach { $0(cleanupError) }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard downloadTask.taskDescription == Self.artifactHash else { downloadTask.cancel(); return }
    received = totalBytesWritten
    let freeBytes = try? Self.directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
    if freeBytes == nil || freeBytes! < 512 * 1024 * 1024 {
      failed = true
      downloadTask.cancel()
      return
    }
    if totalBytesWritten > Self.artifactBytes ||
      (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite != Self.artifactBytes) {
      failed = true
      downloadTask.cancel()
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard !cancelling, downloadTask.taskDescription == Self.artifactHash else { return }
    do {
      guard let response = downloadTask.response as? HTTPURLResponse,
        response.statusCode == 200,
        let url = response.url, Self.permits(url),
        (response.value(forHTTPHeaderField: "Content-Encoding") ?? "identity") == "identity",
        try location.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(Self.artifactBytes) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      try checkStorage()
      // Do not overwrite an existing staging artifact or installed model.
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: location.path)
      try FileManager.default.moveItem(at: location, to: staged)
      var destination = staged
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try destination.setResourceValues(values)
      received = Self.artifactBytes
    } catch {
      failed = true
      try? removeStaging()
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if error != nil { failed = true }
    if task.taskIdentifier == current?.taskIdentifier { current = nil }
    if cancelling {
      // getAllTasks fences callbacks before returning Cancel to Dart.
      tasks { remaining in if remaining.isEmpty { self.finishCancellation() } }
    }
  }

  static func permits(_ url: URL) -> Bool {
    url.scheme == "https" && url.user == nil && url.password == nil &&
      (url.port == nil || url.port == 443) && url.fragment == nil && hosts.contains(url.host ?? "")
  }

  // Background sessions follow redirects themselves. Reject unreviewed TLS
  // hosts and validate the final response before accepting any file.
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    let space = challenge.protectionSpace
    guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      space.protocol == "https", space.port == 443, Self.hosts.contains(space.host) else {
      completionHandler(.cancelAuthenticationChallenge, nil); return
    }
    completionHandler(.performDefaultHandling, nil)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    let completion = backgroundCompletion
    backgroundCompletion = nil
    completion?()
  }
}
