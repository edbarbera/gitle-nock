import Foundation

/// The user's list of folders, persisted between launches.
final class RepoStore {
    private let reposKey = "gitlenock.repos"
    private let activeKey = "gitlenock.activeRepo"
    private let defaults = UserDefaults.standard

    func load() -> [Repo] {
        guard let data = defaults.data(forKey: reposKey),
              let repos = try? JSONDecoder().decode([Repo].self, from: data)
        else { return [] }
        // Deliberately unfiltered. A folder can be temporarily unreachable — an
        // unmounted drive, a folder macOS is gating — and dropping it here would
        // quietly erase the user's list on the next save.
        return repos
    }

    func save(_ repos: [Repo]) {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        defaults.set(data, forKey: reposKey)
    }

    func loadActiveID() -> UUID? {
        guard let raw = defaults.string(forKey: activeKey) else { return nil }
        return UUID(uuidString: raw)
    }

    func saveActiveID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
    }
}
