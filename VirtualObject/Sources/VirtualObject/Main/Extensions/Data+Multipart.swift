// Data+Multipart.swift
import Foundation

extension Data {
    mutating func appendString(_ str: String) {
        if let d = str.data(using: .utf8) { append(d) }
    }
}
