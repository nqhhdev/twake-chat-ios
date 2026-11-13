import MatrixData
import Testing

struct MatrixPlatformTests {
  @Test func setUpCanBeCalledTwice() {
    MatrixPlatform.setUp()
    MatrixPlatform.setUp()
  }

  /// Many callers at once (for example the app and, later, a background task) still set the platform up only once and
  /// never crash: the guard is a static `let`, which Swift initializes once across threads.
  @Test func setUpCanBeCalledFromManyTasksAtOnce() async {
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<32 {
        group.addTask { MatrixPlatform.setUp() }
      }
    }
    MatrixPlatform.setUp()
  }
}
