//
// FormCache.swift
// In-memory cache for forms to enable instant display
//

import Foundation

/// Actor-based cache for forms with TTL-based expiration.
/// Enables instant form display when prefetched during SDK configuration.
actor FormCache {
    static let shared = FormCache()

    private struct CachedForm {
        let form: PaydirtForm
        let fetchedAt: Date
    }

    private var cacheByFormId: [String: CachedForm] = [:]
    private var cacheByType: [String: CachedForm] = [:]

    /// Time-to-live for cached forms (5 minutes)
    private let ttl: TimeInterval = 300

    private init() {}

    /// Get a cached form by ID if it exists and hasn't expired
    func get(formId: String) -> PaydirtForm? {
        guard let cached = cacheByFormId[formId] else {
            return nil
        }

        // Check if cache has expired
        if Date().timeIntervalSince(cached.fetchedAt) > ttl {
            cacheByFormId.removeValue(forKey: formId)
            return nil
        }

        return cached.form
    }

    /// Get a cached form by type if it exists and hasn't expired
    func get(type: String) -> PaydirtForm? {
        guard let cached = cacheByType[type] else {
            return nil
        }

        // Check if cache has expired
        if Date().timeIntervalSince(cached.fetchedAt) > ttl {
            cacheByType.removeValue(forKey: type)
            return nil
        }

        return cached.form
    }

    /// Cache a form by both its ID and type
    func set(form: PaydirtForm) {
        let cached = CachedForm(form: form, fetchedAt: Date())
        cacheByFormId[form.id] = cached
        cacheByType[form.type] = cached
    }

    /// Clear all cached forms (useful for testing or when credentials change)
    func clear() {
        cacheByFormId.removeAll()
        cacheByType.removeAll()
    }
}
