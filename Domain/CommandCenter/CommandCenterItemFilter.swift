import Foundation

/// Shared Command Center list filtering for root + nest rows (Input substring / Normal sequence prefix).
enum CommandCenterItemFilter {
    static func filter(
        _ items: [CommandCenterItem],
        mode: CommandCenterMode,
        query: String
    ) -> [CommandCenterItem] {
        switch mode {
        case .input:
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return items }
            return items.filter { item in
                let hay = [item.title, item.subtitle, item.sequence]
                    .compactMap { $0?.lowercased() }
                    .joined(separator: " ")
                return hay.contains(q)
            }
        case .normal:
            let seq = query.lowercased()
            guard !seq.isEmpty else { return items }
            return items.filter { item in
                guard let chord = item.sequence?.lowercased() else { return false }
                return chord.hasPrefix(seq)
            }
        }
    }
}
