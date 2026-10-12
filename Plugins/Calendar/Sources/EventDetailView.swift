import SwiftUI
import AppKit

struct EventDetailView: View {
    let event: CalendarEventItem
    let onBack: () -> Void
    
    @State private var isHoveringBack = false
    
    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()
    
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return formatter
    }()
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    private var durationText: String? {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        guard duration > 0 else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        var str = ""
        if hours > 0 { str += "\(hours) 小时 " }
        if minutes > 0 { str += "\(minutes) 分钟" }
        return str.isEmpty ? nil : str
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(CalendarTheme.winBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveringBack ? CalendarTheme.winBlue.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .onHover { isHoveringBack = $0 }
                
                Spacer()
                
                Text("日程详情")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                Button(action: openInSystemCalendar) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("在系统日历中打开")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider()
                .opacity(0.3)
            
            // Detail Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // Calendar Category Badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: event.calendarColor) ?? CalendarTheme.winBlue)
                            .frame(width: 8, height: 8)
                        Text(event.calendarTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    // Event Title
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Date & Time Card
                    detailSection(icon: "clock", title: "时间") {
                        VStack(alignment: .leading, spacing: 4) {
                            if event.isAllDay {
                                Text(Self.fullDateFormatter.string(from: event.startDate))
                                    .font(.system(size: 13, weight: .medium))
                                Text("全天日程")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(Self.dateTimeFormatter.string(from: event.startDate)) - \(Self.timeFormatter.string(from: event.endDate))")
                                    .font(.system(size: 13, weight: .medium))
                                
                                if let durationStr = durationText {
                                    Text("时长：\(durationStr)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Location Card
                    if let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailSection(icon: "mappin.and.ellipse", title: "地点") {
                            Text(location)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    // URL / Meeting Link Card
                    if let url = event.url {
                        detailSection(icon: "link", title: "网址与会议链接") {
                            Button(action: {
                                NSWorkspace.shared.open(url)
                            }) {
                                HStack(spacing: 4) {
                                    Text(url.absoluteString)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                }
                                .foregroundColor(CalendarTheme.winBlue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Notes Card
                    if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailSection(icon: "text.alignleft", title: "备注说明") {
                            Text(notes)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Attendees Card
                    if !event.attendees.isEmpty {
                        detailSection(icon: "person.2", title: "参与人") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(event.attendees, id: \.self) { attendee in
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.circle")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 12))
                                        Text(attendee)
                                            .font(.system(size: 12))
                                    }
                                }
                            }
                        }
                    }
                    
                    // Alarms Card
                    if event.hasAlarms {
                        detailSection(icon: "bell", title: "提醒") {
                            Text("已设置系统日程提醒")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(18)
            }
            
            Divider()
                .opacity(0.3)
            
            // Bottom Action Bar
            HStack {
                Button(action: openInSystemCalendar) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("在系统日历中编辑")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(CalendarTheme.winBlue.opacity(0.12))
                    .foregroundColor(CalendarTheme.winBlue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
    }
    
    private func detailSection<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            content()
                .padding(.leading, 18)
        }
    }
    
    private func openInSystemCalendar() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }
}
