import SwiftUI

struct ChatView: View {
  var body: some View {
    if #available(iOS 26, *) {
      Color.clear
    } else {
      Color.gray
    }
  }
}
