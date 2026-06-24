import Foundation

enum ReminderOffset: Int, Codable {
    case atTime    = 0    // 到点提醒
    case oneHour   = 60   // 提前 1 小时（单位：分钟）
    case oneDay    = 1440 // 提前 1 天

    var displayName: String {
        switch self {
        case .atTime:  return "到点提醒"
        case .oneHour: return "提前 1 小时"
        case .oneDay:  return "提前 1 天"
        }
    }

    /// 提前于截止时间的秒数
    var secondsBefore: TimeInterval {
        TimeInterval(rawValue) * 60
    }
}
