import Foundation
import UIKit

struct ClothingIdentifyResult: Equatable {
    var brand: String?
    var color: String?
    var garmentType: String?
    var title: String?
    var size: String?
    var condition: String?
    var suggestedPrice: Double?
    var suggestedPriceMin: Double?
    var suggestedPriceMax: Double?
    var confidence: Confidence
    var matchedProductName: String?
    var sourceUrls: [URL]
    var department: String?
    var warningCode: String?

    enum Confidence: String, Codable, Equatable {
        case low, medium, high
    }

    var suggestedTitle: String {
        if let name = title?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return String(name.prefix(80))
        }
        if let name = matchedProductName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return String(name.prefix(80))
        }
        let parts = [color, brand, garmentType]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let built = parts.joined(separator: " ")
        return String((built.isEmpty ? "Campus listing" : built).prefix(80))
    }

    var isLowConfidence: Bool { confidence == .low }
    var isUnbranded: Bool { warningCode == "NO_BRAND" || brand == nil }
}

struct ListingAIPrefill {
    let images: [UIImage]
    var title: String
    var brand: String
    var color: String
    var garmentType: String
    var department: String?
    var conditionID: String
    var sizeID: String
    var price: String
    var priceMin: Double?
    var priceMax: Double?
    var sourceUrls: [URL]
    var confidence: ClothingIdentifyResult.Confidence
}

enum ClothingIdentifyError: LocalizedError, Equatable {
    case noGarment(String)
    case ambiguous(String)
    case invalidImage(String)
    case rateLimited(String)
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noGarment(let message),
             .ambiguous(let message),
             .invalidImage(let message),
             .rateLimited(let message),
             .unavailable(let message),
             .failed(let message):
            return message
        }
    }

    var retryHint: String {
        switch self {
        case .noGarment: return "Retake with the item filling the frame."
        case .ambiguous: return "Try another angle, or enter the details yourself."
        case .rateLimited: return "Wait a minute, then scan again."
        case .unavailable: return "Check that the API is running, then try again."
        default: return "Take another photo or enter details manually."
        }
    }
}

enum ClothingIdentifyService {
    private struct SuccessDTO: Decodable {
        let brand: String?
        let color: String?
        let garmentType: String?
        let title: String?
        let size: String?
        let condition: String?
        let suggestedPrice: Double?
        let suggestedPriceMin: Double?
        let suggestedPriceMax: Double?
        let confidence: String
        let matchedProductName: String?
        let sourceUrls: [String]?
        let department: String?
        let warningCode: String?
    }

    private struct ErrorDTO: Decodable {
        let code: String?
        let message: String?
    }

    private struct Body: Encodable {
        struct ImagePayload: Encodable {
            let imageBase64: String
            let mediaType: String
        }
        let images: [ImagePayload]
    }

    static func identify(images: [UIImage]) async throws -> ClothingIdentifyResult {
        let payloads: [Body.ImagePayload] = images.prefix(5).compactMap { image in
            guard let jpeg = image.jpegForIdentify(maxDimension: 1100, maxBytes: 450_000) else { return nil }
            return .init(imageBase64: jpeg.base64EncodedString(), mediaType: "image/jpeg")
        }
        guard !payloads.isEmpty else {
            throw ClothingIdentifyError.invalidImage("Couldn’t read those photos. Try another one.")
        }

        let body = try JSONEncoder().encode(Body(images: payloads))
        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        if let token = await APIClient.shared.resolveAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let deviceId = UIDevice.current.identifierForVendor?.uuidString {
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClothingIdentifyError.unavailable("Couldn’t reach the scanner. Check your connection.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClothingIdentifyError.failed("Invalid response from server.")
        }

        if !(200...299).contains(http.statusCode) {
            throw mapError(status: http.statusCode, data: data)
        }

        let dto = try JSONDecoder().decode(SuccessDTO.self, from: data)
        let urls = (dto.sourceUrls ?? []).compactMap { URL(string: $0) }
        let confidence = ClothingIdentifyResult.Confidence(rawValue: dto.confidence.lowercased()) ?? .low
        return ClothingIdentifyResult(
            brand: dto.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            color: dto.color?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            garmentType: dto.garmentType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            title: dto.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            size: dto.size?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            condition: dto.condition?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            suggestedPrice: dto.suggestedPrice,
            suggestedPriceMin: dto.suggestedPriceMin,
            suggestedPriceMax: dto.suggestedPriceMax,
            confidence: confidence,
            matchedProductName: dto.matchedProductName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sourceUrls: urls,
            department: dto.department?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            warningCode: dto.warningCode
        )
    }

    private static func endpoint() throws -> URL {
        var base = SquareConfig.apiBaseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/identify-clothing") else {
            throw ClothingIdentifyError.failed("Invalid server URL.")
        }
        return url
    }

    private static func mapError(status: Int, data: Data) -> ClothingIdentifyError {
        let dto = try? JSONDecoder().decode(ErrorDTO.self, from: data)
        let message = dto?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (dto?.code ?? "").uppercased()
        switch (status, code) {
        case (422, "NO_GARMENT"):
            return .noGarment(message ?? "We couldn’t find a clothing item in that photo.")
        case (422, "AMBIGUOUS"):
            return .ambiguous(message ?? "We’re not sure what this is.")
        case (400, _), (_, "INVALID_IMAGE"):
            return .invalidImage(message ?? "That photo couldn’t be scanned.")
        case (429, _), (_, "RATE_LIMITED"):
            return .rateLimited(message ?? "Too many scans. Try again shortly.")
        case (503, _), (_, "API_UNAVAILABLE"):
            return .unavailable(message ?? "The scanner is unavailable right now.")
        default:
            return .failed(message ?? "Scan failed. Try another photo.")
        }
    }
}

enum SellListingLookups {
    static let conditions: [(id: String, name: String)] = [
        ("new", "Brand New"),
        ("like-new", "Like New"),
        ("good", "Good"),
        ("fair", "Fair"),
    ]

    static let sizes: [(id: String, name: String)] = [
        ("xxs", "XXS"),
        ("xs", "XS"),
        ("s", "S"),
        ("m", "M"),
        ("l", "L"),
        ("xl", "XL"),
        ("xxl", "XXL"),
        ("xxxl", "XXXL"),
        ("one-size", "One Size"),
        ("other", "Other"),
    ]

    static func conditionName(id: String) -> String? {
        conditions.first { $0.id == id }?.name
    }

    static func sizeName(id: String) -> String? {
        sizes.first { $0.id == id }?.name
    }

    static func conditionID(from raw: String?) -> String {
        let v = (raw ?? "").lowercased().replacingOccurrences(of: " ", with: "-")
        if conditions.contains(where: { $0.id == v }) { return v }
        if v.contains("brand-new") || v == "new" { return "new" }
        if v.contains("like") { return "like-new" }
        if v.contains("fair") || v.contains("poor") { return "fair" }
        if v.contains("good") { return "good" }
        return ""
    }

    static func sizeID(from raw: String?) -> String {
        let v = (raw ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        if v.isEmpty { return "" }
        if let match = sizes.first(where: { $0.id == v || $0.name.lowercased().replacingOccurrences(of: " ", with: "") == v }) {
            return match.id
        }
        switch v {
        case "small": return "s"
        case "medium": return "m"
        case "large": return "l"
        case "os", "onesize": return "one-size"
        default: return ""
        }
    }

    static func departmentLabel(_ department: String?) -> String? {
        switch (department ?? "").lowercased() {
        case "mens", "men": return "Men"
        case "womens", "women": return "Women"
        case "unisex": return "Unisex"
        default: return nil
        }
    }

    static func categoryDisplay(garmentType: String, department: String?) -> String {
        let type = garmentType.trimmingCharacters(in: .whitespacesAndNewlines)
        if type.isEmpty { return "" }
        if let dept = departmentLabel(department) {
            return "\(dept) · \(type.capitalized)"
        }
        return type.capitalized
    }

    static func priceString(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    static func priceRangeLabel(min: Double?, max: Double?) -> String? {
        guard let min, let max, min > 0, max >= min else { return nil }
        let low = priceString(min) ?? ""
        let high = priceString(max) ?? ""
        guard !low.isEmpty, !high.isEmpty else { return nil }
        if low == high { return "$\(low)" }
        return "$\(low)–$\(high)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UIImage {
    func jpegForIdentify(maxDimension: CGFloat = 1280, maxBytes: Int = 900_000) -> Data? {
        let scaled = resizedForIdentify(maxDimension: maxDimension)
        var quality: CGFloat = 0.78
        var data = scaled.jpegData(compressionQuality: quality)
        while let current = data, current.count > maxBytes, quality > 0.4 {
            quality -= 0.1
            data = scaled.jpegData(compressionQuality: quality)
        }
        return data
    }

    fileprivate func resizedForIdentify(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
