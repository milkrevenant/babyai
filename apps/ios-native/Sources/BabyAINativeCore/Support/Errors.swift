import Foundation

public enum BabyAIError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case missingBearerToken
    case missingBabyID
    case missingHouseholdID
    case missingAlbumID
    case invalidResponseShape
    case unexpectedStatusCode(Int, String?)
    case routeDrift(RouteDriftEndpoint)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .missingBearerToken:
            return "Bearer token is required"
        case .missingBabyID:
            return "baby_id is required"
        case .missingHouseholdID:
            return "household_id is required"
        case .missingAlbumID:
            return "album_id is required"
        case .invalidResponseShape:
            return "Unexpected API response shape"
        case let .unexpectedStatusCode(status, message):
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "HTTP \(status): \(message)"
            }
            return "HTTP \(status)"
        case let .routeDrift(endpoint):
            return "Blocked by route drift: \(endpoint.path) is not in router source-of-truth"
        case let .transport(message):
            return message
        }
    }
}
