/// Raw GitHub Releases API candidate. Optional edge fields let one malformed
/// candidate fail closed without hiding other valid releases in the feed.
struct GitHubRelease: Codable, Equatable, Sendable {
    let tagName: String?
    let htmlURL: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
    }
}
