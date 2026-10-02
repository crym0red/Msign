import Foundation
import SwiftUI
import WidgetKit

private let mSignAppGroup = "group.com.mrzefv.unzipDrop"
private let mSignWidgetKey = "msignWidgetData"

struct MSignWidgetData: Codable {
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

    static let empty = MSignWidgetData(
        username: "mSign",
        mdid: "",
        role: "",
        today: 0,
        running: 0,
        failed: 0,
        averageSeconds: nil,
        recent: [],
        updatedAt: Date()
    )

    static func load() -> MSignWidgetData {
        guard
            let defaults = UserDefaults(suiteName: mSignAppGroup),
            let data = defaults.data(forKey: mSignWidgetKey),
            let value = try? JSONDecoder().decode(MSignWidgetData.self, from: data)
        else { return .empty }
        return value
    }
}

struct MSignWidgetEntry: TimelineEntry {
    let date: Date
    let data: MSignWidgetData
}

struct MSignWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MSignWidgetEntry {
        MSignWidgetEntry(date: Date(), data: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (MSignWidgetEntry) -> Void) {
        completion(MSignWidgetEntry(date: Date(), data: MSignWidgetData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MSignWidgetEntry>) -> Void) {
        let entry = MSignWidgetEntry(date: Date(), data: MSignWidgetData.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct MSignWidget: Widget {
    let kind = "MSignWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MSignWidgetProvider()) { entry in
            MSignWidgetView(entry: entry)
        }
        .configurationDisplayName("mSign")
        .description("See mSign signing activity and Turbo status.")
        .supportedFamilies([
            .systemMedium,
            .accessoryRectangular
        ])
    }
}

@main
struct MSignWidgetBundle: WidgetBundle {
    var body: some Widget {
        MSignWidget()
    }
}

private struct MSignWidgetView: View {
    let entry: MSignWidgetEntry

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                content
                    .containerBackground(.black, for: .widget)
            } else {
                content
                    .background(Color.black)
            }
        }
        .widgetURL(URL(string: "msign://activity"))
    }

    @ViewBuilder
    private var content: some View {
        FamilyAwareMSignContent(data: entry.data)
    }
}

private struct FamilyAwareMSignContent: View {
    @Environment(\.widgetFamily) private var family
    let data: MSignWidgetData

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                accessory
            } else {
                medium
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(red: 0.45, green: 1.0, blue: 0.50))
                .frame(width: 26, height: 26)
                .overlay(Text("M").font(.system(size: 14, weight: .black)).foregroundStyle(.black))
            VStack(alignment: .leading, spacing: 1) {
                Text(data.username.isEmpty ? "mSign" : data.username)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !data.mdid.isEmpty {
                    Text(data.mdid)
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer()
            if !data.role.isEmpty {
                Text(data.role.uppercased())
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.30))
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            HStack(spacing: 8) {
                stat("⚡", "TURBO", "\(data.running) active")
                Link(destination: URL(string: "msign://import")!) {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Drop IPA")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 0.45, green: 1.0, blue: 0.50))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
            }
            HStack(spacing: 7) {
                metric("\(data.today)", "Today")
                metric("\(data.running)", "Running")
                metric("\(data.failed)", "Failed")
                if let avg = data.averageSeconds {
                    metric(String(format: "%.1fs", avg), "Avg")
                }
            }
            if !data.recent.isEmpty {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(data.recent.prefix(3)) { item in
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol)
                            .frame(width: 17)
                            .foregroundStyle(item.succeeded ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(item.detail).font(.system(size: 7, design: .monospaced)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: item.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(item.succeeded ? Color.green : Color.orange)
                    }
                }
            } else {
                Text("No signing activity yet")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(12)
    }

    private var accessory: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(data.username.isEmpty ? "mSign" : data.username)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("⚡ \(data.running) active  •  \(data.today) today")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let first = data.recent.first {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: first.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(first.succeeded ? Color.green : Color.orange)
                    if let avg = data.averageSeconds {
                        Text(String(format: "%.1fs", avg))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    }
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func stat(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 7) {
            Text(symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced))
                Text(subtitle).font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .foregroundStyle(Color(red: 0.45, green: 1.0, blue: 0.50))
        .padding(9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            Text(label.uppercased()).font(.system(size: 6, weight: .heavy, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

private extension MSignWidgetData {
    static var preview: MSignWidgetData {
        MSignWidgetData(
            username: "MRZefV",
            mdid: "MS-2MUPSW-ZM",
            role: "ADMIN",
            today: 3,
            running: 1,
            failed: 0,
            averageSeconds: 8.4,
            recent: [
                Activity(id: "1", name: "AudioMack 8.9.0", detail: "Signed · 8.2s", symbol: "music.note", succeeded: true),
                Activity(id: "2", name: "ExampleApp 2.1.4", detail: "Signed · 7.4s", symbol: "app.fill", succeeded: true),
                Activity(id: "3", name: "AudioMack 8.7.0", detail: "Signed · 9.1s", symbol: "music.note", succeeded: true)
            ],
            updatedAt: Date()
        )
    }
}
