import Foundation

final class LastTvStore: LastTvStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "lastTvRecord") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> LastTvRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(LastTvRecord.self, from: data)
    }

    func save(_ record: LastTvRecord) throws {
        defaults.set(try JSONEncoder().encode(record), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

