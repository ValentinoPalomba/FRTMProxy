import Foundation

extension DateFormatter {
    static let cachedTime: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
}

