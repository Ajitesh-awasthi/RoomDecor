import Foundation

// ============================================================================
// SMART CATEGORY RESOLUTION SYSTEM
// ============================================================================
// Add this to CategoryResolver.swift or a separate configuration file
let furnitureAssets: [String: String] = [
    "Sofa": "sofa_model",
    "Table": "table_model",
    "Office Chair": "chair_model",
    "Bookshelf": "bookshelf_model",
    "Bed": "bed_model",
    "Lamp": "lamp_model",
    "Wardrobe": "wardrobe_model",
    "Pot": "pot_model"
]
/// Resolves furniture categories intelligently using fuzzy matching and semantic understanding
class CategoryResolver {
    
    // Base categories that we have 3D models for
    private static let baseCategoryMappings: [String: [String]] = [
        "Sofa": ["sofa", "couch", "settee", "loveseat", "sectional"],
        "Table": ["table", "desk", "stand", "counter", "surface"],
        "Office Chair": ["chair", "seat", "stool", "armchair"],
        "Bookshelf": ["shelf", "bookcase", "shelving", "rack", "cabinet"],
        "Bed": ["bed", "cot", "mattress"],
        "Lamp": ["lamp", "light", "lighting", "fixture"],
        "Wardrobe": ["wardrobe", "closet", "armoire", "dresser"],
        "Pot": ["pot", "plant", "planter", "vase"]
    ]
    
    
    // Specific sub-category rules
    private static let specificMappings: [String: String] = [
        // Seating
        "armchair": "Sofa",
        "recliner": "Sofa",
        "bean bag": "Sofa",
        
        // Tables
        "coffee table": "Table",
        "side table": "Table",
        "end table": "Table",
        "console table": "Table",
        "tv stand": "Table",
        "tv unit": "Table",
        "media console": "Table",
        
        // Storage
        "nightstand": "Table",
        "bedside table": "Table",
        "drawer": "Wardrobe",
        "chest": "Wardrobe",
        
        // Chairs
        "dining chair": "Office Chair",
        "desk chair": "Office Chair",
        "lounge chair": "Sofa"
    ]
    
    /// Resolve a category name to the closest base category
    static func resolve(_ category: String) -> String? {
        let normalized = normalize(category)
        
        // 1. Try exact match first
        if baseCategoryMappings.keys.contains(where: { normalize($0) == normalized }) {
            return baseCategoryMappings.keys.first { normalize($0) == normalized }
        }
        
        // 2. Try specific mappings
        if let mapped = specificMappings[normalized] {
            print("📎 Mapped '\(category)' → '\(mapped)' (specific rule)")
            return mapped
        }
        
        // 3. Try fuzzy matching with keywords
        for (baseCategory, keywords) in baseCategoryMappings {
            for keyword in keywords {
                if normalized.contains(keyword) || keyword.contains(normalized) {
                    print("📎 Fuzzy matched '\(category)' → '\(baseCategory)' (keyword: \(keyword))")
                    return baseCategory
                }
            }
        }
        
        // 4. Try semantic similarity (word overlap)
        if let match = findBestSemanticMatch(normalized) {
            return match
        }
        
        print("⚠️ Could not resolve category: '\(category)'")
        return nil
    }
    
    /// Normalize category string for matching
    private static func normalize(_ text: String) -> String {
        return text
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// Find best semantic match using word similarity
    private static func findBestSemanticMatch(_ normalized: String) -> String? {
        let words = normalized.split(separator: " ").map(String.init)
        
        var bestMatch: String?
        var bestScore = 0
        
        for (baseCategory, keywords) in baseCategoryMappings {
            let categoryWords = normalize(baseCategory).split(separator: " ").map(String.init)
            
            // Count common words
            let commonWords = Set(words).intersection(Set(categoryWords + keywords))
            let score = commonWords.count
            
            if score > bestScore {
                bestScore = score
                bestMatch = baseCategory
            }
        }
        
        if bestScore > 0 {
            print("📎 Semantic match '\(normalized)' → '\(bestMatch!)' (score: \(bestScore))")
            return bestMatch
        }
        
        return nil
    }
    
    static func getAssetName(for category: String) -> String? {
        guard let resolved = resolve(category) else { return nil }
        return furnitureAssets[resolved]
    }
}

// ============================================================================
// EXTENSION: Smart Asset Lookup
// ============================================================================

extension Dictionary where Key == String, Value == String {
    
    /// Smart subscript that tries to resolve category automatically
    subscript(smart category: String) -> String? {
        // Try direct lookup first
        if let direct = self[category] {
            return direct
        }
        
        // Try resolution
        if let resolved = CategoryResolver.resolve(category) {
            return self[resolved]
        }
        
        return nil
    }
}
