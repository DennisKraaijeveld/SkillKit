import os

enum SkillbookSignposts {
    static let operations = OSSignposter(
        subsystem: "com.denniskraaijeveld.skillkit",
        category: "Operations"
    )
    static let rendering = OSSignposter(
        subsystem: "com.denniskraaijeveld.skillkit",
        category: "Rendering"
    )
}
