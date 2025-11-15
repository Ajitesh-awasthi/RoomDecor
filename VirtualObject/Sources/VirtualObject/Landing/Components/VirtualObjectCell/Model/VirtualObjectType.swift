import Foundation
import Core

public enum VirtualObjectType: String, CaseIterable {

    case armchair
    case chair
    case smallShelf
    case lamp
    case sideTable
    case shelf
    case stool
    case table

    // human-friendly title used in UI
    var title: String {
        switch self {
        case .armchair:
            return LocalizableStrings.armchair.localized
        case .chair:
            return LocalizableStrings.chair.localized
        case .smallShelf:
            return LocalizableStrings.smallShelf.localized
        case .lamp:
            return LocalizableStrings.lamp.localized
        case .sideTable:
            return LocalizableStrings.sideTable.localized
        case .shelf:
            return LocalizableStrings.shelf.localized
        case .stool:
            return LocalizableStrings.stool.localized
        case .table:
            return LocalizableStrings.table.localized
        }
    }

    // thumbnail image name convention: "<raw>_thumb"
    var thumbnailImageName: String {
        return rawValue + "_thumb"
    }

    // explicit usdz filename (adjust if your project expects different extension format)
    var usdzFileName: String {
        return rawValue + ".usdz"
    }
}
