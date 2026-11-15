import CryptoKit
import Flutter
import Foundation

/// One pinned, public catalogue file: where it comes from, what it must be,
/// and the staging file it lands in. Encoded in the task description so a
/// transfer finished while Sekret was not running is still checked.
struct ReviewedTransfer: Equatable {
  static func == (a: Self, b: Self) -> Bool {
    a.url == b.url && a.sha256 == b.sha256 && a.bytes == b.bytes && a.lands(at: b.destination)
  }

  func lands(at url: URL) -> Bool {
    destination.standardizedFileURL.path == url.standardizedFileURL.path
  }

  let url: URL
  let sha256: String
  let bytes: Int64
  let destination: URL

  /// Files staged before per-model folders: Qwen3-4B's single transfer.
  static let legacyHash = "9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9"
  static let legacyBytes: Int64 = 2_075_618_400
  static let legacyURL = URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q3_K_M.gguf")!

  var taskDescription: String {
    "v2 \(sha256) \(bytes) \(ModelDownloadPlugin.relative(destination) ?? "")"
  }

  init?(url: URL, sha256: String, bytes: Int64, destination: URL) {
    guard ModelDownloadPlugin.reviewed(url), bytes > 0,
      sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
      ModelDownloadPlugin.relative(destination) != nil else { return nil }
    self.url = url
    self.sha256 = sha256
    self.bytes = bytes
    self.destination = destination
  }

  /// The original request URL is checked again, so a description alone
  /// cannot widen what a task may deliver.
  init?(task: URLSessionTask) {
    guard let description = task.taskDescription, let url = task.originalRequest?.url else { return nil }
    if description == Self.legacyHash {
      guard url == Self.legacyURL else { return nil }
      self.init(url: url, sha256: Self.legacyHash, bytes: Self.legacyBytes,
                destination: ModelDownloadPlugin.directory.appendingPathComponent("download.partial"))
      return
    }
    let parts = description.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 4, parts[0] == "v2", let bytes = Int64(parts[2]) else { return nil }
    self.init(url: url, sha256: parts[1], bytes: bytes,
              destination: ModelDownloadPlugin.directory.appendingPathComponent(parts[3]))
  }
}

/// Only public catalogue files use this session. Private data never enters it.
/// URLSession owns transfer execution while Flutter is suspended. One file
/// transfers at a time, for every model; Dart verifies and publishes it.
final class ModelDownloadPlugin: NSObject, FlutterPlugin, URLSessionDownloadDelegate {
  static let shared = ModelDownloadPlugin()
  static let identifier = "com.ricejy.sekret.reviewed-model-download"
  static let hosts: Set<String> = ["huggingface.co", "cdn-lfs.huggingface.co", "cdn-lfs-us-1.huggingface.co", "cdn-lfs-eu-1.huggingface.co", "cas-bridge.xethub.hf.co", "us.aws.cdn.hf.co"]
  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("reviewed-models", isDirectory: true)
  }
  private var current: URLSessionDownloadTask?
  private var transfer: ReviewedTransfer?
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

  /// A pinned Hugging Face file URL: an exact 40-hex commit, no query.
  static func reviewed(_ url: URL) -> Bool {
    guard permits(url), url.host == "huggingface.co", url.query == nil else { return false }
    return url.path.range(
      of: "^/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/resolve/[0-9a-f]{40}/[A-Za-z0-9_][A-Za-z0-9._/-]*$",
      options: .regularExpression) != nil && !url.path.contains("/../")
  }

  /// A staging path Sekret owns: the legacy single file, or
  /// `<model-id>/<sha256>.partial`. Nothing else is ever written.
  static func relative(_ url: URL) -> String? {
    let root = directory.standardizedFileURL.path + "/"
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(root) else { return nil }
    let rest = String(path.dropFirst(root.count))
    let pattern = "^(download\\.partial|[a-z0-9][a-z0-9.-]*/[0-9a-f]{64}\\.partial)$"
    return rest.range(of: pattern, options: .regularExpression) != nil ? rest : nil
  }

  /// An owned file below the directory, reached without links.
  static func owned(_ url: URL) -> Bool {
    let root = directory.standardizedFileURL.path + "/"
    let path = url.standardizedFileURL.path
    return path.hasPrefix(root) && !path.contains("/../") &&
      url.standardizedFileURL == url.resolvingSymlinksInPath()
  }

  func reconnect() { _ = session }

  private func tasks(_ completion: @escaping ([URLSessionTask]) -> Void) {
    session.getAllTasks { tasks in DispatchQueue.main.async { completion(tasks) } }
  }

  private func adopt(_ tasks: [URLSessionTask]) {
    current = tasks.compactMap { $0 as? URLSessionDownloadTask }.first { ReviewedTransfer(task: $0) != nil }
    transfer = current.flatMap { ReviewedTransfer(task: $0) }
    if let current { received = max(0, current.countOfBytesReceived) }
  }

  private func checkStorage(_ staged: URL) throws {
    let root = Self.directory
    let folder = staged.deletingLastPathComponent()
    guard root.standardizedFileURL == root.resolvingSymlinksInPath(),
      folder.standardizedFileURL == folder.resolvingSymlinksInPath(),
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
    // Dart creates the model's folder before the first transfer.
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
      throw CocoaError(.fileWriteNoPermission)
    }
  }

  private func removeStaging(_ staged: URL) throws {
    try checkStorage(staged)
    if FileManager.default.fileExists(atPath: staged.path) {
      try FileManager.default.removeItem(at: staged)
    }
  }

  private func destination(_ call: FlutterMethodCall) -> URL? {
    guard let path = (call.arguments as? [String: Any])?["destination"] as? String else { return nil }
    let url = URL(fileURLWithPath: path)
    return Self.relative(url) != nil ? url : nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPending":
      guard let staged = destination(call) else { result(error()); return }
      tasks { tasks in
        self.adopt(tasks)
        result(self.transfer?.lands(at: staged) == true || FileManager.default.fileExists(atPath: staged.path))
      }
    case "start":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let url = (args["url"] as? String).flatMap(URL.init(string:)),
        let sha256 = args["sha256"] as? String,
        let bytes = (args["bytes"] as? NSNumber)?.int64Value,
        let staged = destination(call),
        let requested = ReviewedTransfer(url: url, sha256: sha256, bytes: bytes, destination: staged),
        !cancelling else {
        result(error()); return
      }
      tasks { tasks in
        guard !self.cancelling else { result(self.error()); return }
        self.adopt(tasks)
        do {
          try self.checkStorage(staged)
          if let running = self.transfer, running != requested {
            // One transfer at a time; the other must finish or be cancelled.
            result(self.error()); return
          }
          if self.current == nil && !FileManager.default.fileExists(atPath: staged.path) {
            self.failed = false
            self.received = 0
            var request = URLRequest(url: requested.url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let task = self.session.downloadTask(with: request)
            task.countOfBytesClientExpectsToReceive = requested.bytes
            task.taskDescription = requested.taskDescription
            self.current = task
            self.transfer = requested
            task.resume()
          }
          result(nil)
        } catch { result(self.error()) }
      }
    case "status":
      guard let staged = destination(call) else { result(error()); return }
      if FileManager.default.fileExists(atPath: staged.path) && !cancelling {
        let size = (try? staged.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        result(["phase": "complete", "bytes": Int64(size)])
      } else {
        let mine = transfer?.lands(at: staged) == true
        result(["phase": failed || current == nil || !mine ? "failed" : "downloading", "bytes": mine ? received : 0])
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
      // Only files Sekret owns below reviewed-models; hashed off the main thread.
      let path = (call.arguments as? [String: Any])?["path"] as? String
      guard let path, Self.owned(URL(fileURLWithPath: path)) else {
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
    let staged = transfer?.destination
    current = nil
    transfer = nil
    received = 0
    failed = true
    var cleanupError: FlutterError?
    if let staged {
      do { try removeStaging(staged) } catch { cleanupError = self.error() }
    }
    cancelling = false
    let waiters = cancelWaiters
    cancelWaiters.removeAll()
    waiters.forEach { $0(cleanupError) }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard let expected = ReviewedTransfer(task: downloadTask) else { downloadTask.cancel(); return }
    received = totalBytesWritten
    let freeBytes = try? Self.directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
    if freeBytes == nil || freeBytes! < 512 * 1024 * 1024 {
      failed = true
      downloadTask.cancel()
      return
    }
    if totalBytesWritten > expected.bytes ||
      (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite != expected.bytes) {
      failed = true
      downloadTask.cancel()
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard !cancelling, let expected = ReviewedTransfer(task: downloadTask) else { return }
    let staged = expected.destination
    do {
      guard let response = downloadTask.response as? HTTPURLResponse,
        response.statusCode == 200,
        let url = response.url, Self.permits(url),
        (response.value(forHTTPHeaderField: "Content-Encoding") ?? "identity") == "identity",
        try location.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(expected.bytes) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      try checkStorage(staged)
      // Do not overwrite an existing staging artifact or installed model.
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: location.path)
      try FileManager.default.moveItem(at: location, to: staged)
      var destination = staged
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try destination.setResourceValues(values)
      received = expected.bytes
    } catch {
      failed = true
      try? removeStaging(staged)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if error != nil { failed = true }
    if task.taskIdentifier == current?.taskIdentifier {
      current = nil
      // Keep the destination so status can still report this file.
    }
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
