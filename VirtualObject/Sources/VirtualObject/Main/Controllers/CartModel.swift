//
//  CartModel.swift
//  Shopping
//
//  Created by Berkay Sancar on 31.07.2024.
//

import Foundation

//MARK: Model with ObservableObject and Codable implemets sample

public class CartModel: ObservableObject, Codable {
  
    enum CodingKeys: CodingKey {
        case id, title, price, brand, images, count
    }
    
    public var id: Int = 0
    public var title: String = ""
    public var price: Double = 0
    public var images: [String] = []
    @Published var count: Int = 1
    
    static var sampleCartModel: CartModel {
        let cartModel = CartModel()
        cartModel.id = 1
        cartModel.count = 1
        cartModel.images = ["https://cdn.dummyjson.com/products/images/fragrances/Dolce%20Shine%20Eau%20de/3.png"]
        cartModel.price = 3.3333
        cartModel.title = "Ayakkabııııııııııııı"
        return cartModel
    }
    
    init() {}

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(price, forKey: .price)
        try container.encode(count, forKey: .count)
        try container.encode(images, forKey: .images)
    }
        
    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.price = try container.decode(Double.self, forKey: .price)
        self.images = try container.decode([String].self, forKey: .images)
        self.count = try container.decode(Int.self, forKey: .count)
    }
}

extension CartModel: Hashable {
    public static func == (lhs: CartModel, rhs: CartModel) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.price == rhs.price &&
               lhs.images == rhs.images
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(price)
        hasher.combine(images)
    }
}
