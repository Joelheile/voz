import os

enum Log {
    static let subsystem = "com.joelheile.voz"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let extensions = Logger(subsystem: subsystem, category: "extensions")
}
