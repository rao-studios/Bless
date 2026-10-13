//
//  BlessLogger.swift
//  Bless
//
//  Created by Ritesh Pakala Rao on 10/13/26.
//

import Foundation
import os

class BlessLogger {
    enum Category: String {
        case base
        
        var logger: Logger {
            switch self {
            case .base:
                BlessLogger.baseLogger
            }
        }
    }
    
    private static let baseLogger = Logger(
        subsystem: "bless-cli",
        category: Category.base.rawValue
    )
    
    static func log(
        _ value: String,
        level osLogType: OSLogType = .info,
        category: Category = .base
    ) {
        category.logger.log(level: osLogType, "\(value)")
    }
}
