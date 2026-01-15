// By Dennis Müller

import Foundation

enum Stderr {
  static func print(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}
