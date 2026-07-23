import Foundation

/// Auto Three-Word Name for Agent Worktree folders (ADR 0017, 0018).
///
/// Pattern: `{word}-{word}-{word}` — lowercase, hyphen-separated, fixed word list.
enum ThreeWordName {
    enum GenerationError: LocalizedError, Equatable {
        case exhausted

        var errorDescription: String? {
            switch self {
            case .exhausted:
                return "Could not generate a unique Three-Word Name after many attempts."
            }
        }
    }

    /// Fixed lowercase word list for auto names.
    static let words: [String] = [
        "amber", "anchor", "apricot", "ash", "aurora", "azure",
        "badge", "basin", "beacon", "birch", "blaze", "bloom", "blue", "brave", "breeze", "brisk",
        "cactus", "candy", "cedar", "chalk", "cinder", "clear", "cliff", "cloud", "cobalt", "comet",
        "coral", "crane", "creek", "crisp", "crown",
        "dawn", "delta", "dew", "dune",
        "eagle", "ember", "ever",
        "fable", "field", "flint", "flora", "fog", "forest", "frost",
        "gale", "garden", "glade", "glow", "gold", "grape", "green",
        "harbor", "haze", "heath", "honey",
        "ivory",
        "jade", "jazz", "jewel",
        "keen", "kettle", "kite", "knight",
        "lagoon", "lake", "lantern", "leaf", "lemon", "light", "lilac", "lime", "lotus", "lunar",
        "maple", "marble", "meadow", "mint", "mist", "moss",
        "navy", "noble", "north",
        "oak", "ocean", "olive", "onyx", "opal",
        "peach", "pearl", "pine", "pixel", "plume", "pond", "prism",
        "quartz", "quiet",
        "rain", "raven", "reef", "ridge", "river", "robin", "rose", "ruby",
        "sage", "sand", "scarlet", "shadow", "shell", "silver", "sky", "slate", "snow", "spark",
        "spice", "spring", "star", "stone", "storm", "summit",
        "tide", "timber", "topaz", "trail",
        "valley", "velvet", "violet",
        "wave", "wheat", "willow", "wind", "wolf",
        "yellow",
        "zephyr", "zinc",
    ]

    /// Generate one random Three-Word Name (no collision check).
    static func generate(using rng: inout some RandomNumberGenerator) -> String {
        let a = words.randomElement(using: &rng)!
        let b = words.randomElement(using: &rng)!
        let c = words.randomElement(using: &rng)!
        return "\(a)-\(b)-\(c)"
    }

    /// Generate a Three-Word Name not present in `existing` folder names.
    static func generateUnique(
        existing: Set<String>,
        maxAttempts: Int = 64,
        using rng: inout some RandomNumberGenerator
    ) throws -> String {
        for _ in 0..<maxAttempts {
            let name = generate(using: &rng)
            if !existing.contains(name) {
                return name
            }
        }
        throw GenerationError.exhausted
    }

    /// Convenience with `SystemRandomNumberGenerator`.
    static func generateUnique(existing: Set<String>, maxAttempts: Int = 64) throws -> String {
        var rng = SystemRandomNumberGenerator()
        return try generateUnique(existing: existing, maxAttempts: maxAttempts, using: &rng)
    }
}
