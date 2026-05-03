//
//  Item.swift
//  quaynor_swift
//
//  Created by Ibrahim Rayamah on 4.05.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
