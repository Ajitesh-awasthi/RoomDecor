//
//  OrderModel.swift
//  Shopping
//
//  Created by Berkay Sancar on 3.08.2024.
//

import Foundation

struct OrderModel: Codable, Hashable {
    var id = UUID().uuidString
    let total: Double
    let cart: [CartModel]
}
