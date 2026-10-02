//
//  WidgetSupport.swift
//  Shared app-side writer for the mSign WidgetKit extension.
//
import Foundation
import WidgetKit

let appGroupID = "group.com.mrzefv.unzipDrop"
private let widgetDataKey = "msignWidgetData"

struct WidgetData: Codable {
    struct Activity: Codable, Identifiable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let succeeded: Bool
    }

    let username: String
    let mdid: String
    let role: String
    let today: Int
    let running: Int
    let failed: Int
    let averageSeconds: Double?
    let recent: [Activity]
    let updatedAt: Date
}

@MainActor
final class WidgetDataManager {
    static let shared = WidgetDataManager()
    private var runtimeRunning = 0
    private var runtimeFailed = 0

    func refresh() {
        let account = ZefvAccount.shared
        let signed = SignedStore.shared
        let calendar = Calendar.current
        let todayEntries = signed.entries.filter { calendar.isDateInToday($0.signedAt) }

        let recent = signed.entries.prefix(5).map { entry in
            WidgetData.Activity(
                id: entry.id,
                name: "\(entry.name) \(entry.version)",
                detail: "Signed · \(relative(entry.signedAt))",
                symbol: "checkmark.seal.fill",
                succeeded: true
            )
        }

        let data = WidgetData(
            username: account.username ?? "mSign",
            mdid: CertificateStore.knownUDID() ?? "",
            role: account.role == .member ? "" : account.role.badgeText,
            today: max(account.signsToday, todayEntries.count),
            running: runtimeRunning,
            failed: runtimeFailed,
            averageSeconds: nil,
            recent: Array(recent),
            updatedAt: Date()
        )
        write(data)
    }

    func setBulkState(running: Int, failed: Int) {
        runtimeRunning = max(0, running)
        runtimeFailed = max(0, failed)
        refresh()
    }

    func updateAfterSigning() {
        runtimeRunning = 0
        refresh()
    }

    private func relative(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    private func write(_ value: WidgetData) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let encoded = try? JSONEncoder().encode(value) else { return }
        defaults.set(encoded, forKey: widgetDataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
