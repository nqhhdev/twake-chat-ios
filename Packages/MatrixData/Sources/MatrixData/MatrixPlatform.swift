import MatrixRustSDK

/// Sets up the Matrix SDK's platform (its tokio runtime and its logs). Without it, `Client.login` and
/// `Client.restoreSession` can wait forever.
public enum MatrixPlatform {
  /// Calls the SDK's `initPlatform` once per process, before any client is built. Later calls do nothing; a failure is
  /// swallowed, because the SDK then runs with whatever platform it has.
  public static func setUp() {
    _ = isSetUp
  }

  /// Swift runs a static `let` initializer once, safely across threads, so `initPlatform` is reached once.
  private static let isSetUp: Bool = {
    #if DEBUG
      let logLevel = LogLevel.info
      let writeToStdoutOrSystem = true
    #else
      let logLevel = LogLevel.warn
      let writeToStdoutOrSystem = false
    #endif
    // No trace log packs and no level below info: the SDK's logs then carry no message content.
    let config = TracingConfiguration(
      logLevel: logLevel, traceLogPacks: [], extraTargets: [],
      writeToStdoutOrSystem: writeToStdoutOrSystem, writeToFiles: nil, sentryConfig: nil)
    do {
      try initPlatform(config: config, useLightweightTokioRuntime: false)
      return true
    } catch {
      return false
    }
  }()
}
