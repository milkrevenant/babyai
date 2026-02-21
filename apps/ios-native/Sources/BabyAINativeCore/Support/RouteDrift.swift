import Foundation

public enum RouteDriftEndpoint: String, CaseIterable, Sendable {
    case photosUpload = "/api/v1/photos/upload"
    case photosRecent = "/api/v1/photos/recent"
    case quickLastFeeding = "/api/v1/quick/last-feeding"
    case quickRecentSleep = "/api/v1/quick/recent-sleep"
    case quickLastDiaper = "/api/v1/quick/last-diaper"
    case quickLastMedication = "/api/v1/quick/last-medication"

    public var path: String {
        rawValue
    }
}
