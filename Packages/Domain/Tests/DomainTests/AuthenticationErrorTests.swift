import Domain
import Testing

struct AuthenticationErrorTests {
  @Test func casesAreDistinct() {
    let all: [AuthenticationError] = [
      .invalidCredentials, .serverUnreachable, .invalidHomeserverURL, .unknown,
    ]
    for (i, a) in all.enumerated() {
      for (j, b) in all.enumerated() {
        #expect((a == b) == (i == j))
      }
    }
  }
}
