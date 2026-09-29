import Foundation

nonisolated enum RcloneProjectionFormat {
    static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(value)
        var unit = 0
        while size >= 1_000 && unit < units.count - 1 {
            size /= 1_000
            unit += 1
        }
        if unit == 0 { return "\(value) B" }
        return String(format: "%.1f %@", size, units[unit])
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Not available" }
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        if hours >= 24 { return String(format: "%dd %dh", hours / 24, hours % 24) }
        if hours > 0 { return String(format: "%dh %dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, remainingSeconds) }
        return "\(remainingSeconds)s"
    }
}
