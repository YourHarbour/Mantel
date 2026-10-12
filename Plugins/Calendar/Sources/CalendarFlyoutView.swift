import SwiftUI
import AppKit

enum CalendarViewMode {
    case days
    case months
    case years
}

struct CalendarFlyoutView: View {
    @StateObject private var stateManager = CalendarStateManager.shared
    @StateObject private var eventService = EventService.shared
    @Namespace private var calendarAnimation
    
    @State private var viewMode: CalendarViewMode = .days
    @State private var displayedDate: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var inspectingEvent: CalendarEventItem? = nil
    @State private var gridData: MonthGridData = CalendarHelper.generateMonthGrid(for: Date(), startOnMonday: true)
    
    var onPinToDesktop: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    
    private var startOnMonday: Bool {
        stateManager.startOnMonday
    }
    
    private var showLunar: Bool {
        stateManager.showLunar
    }
    
    private var calendarContentHeight: CGFloat {
        switch viewMode {
        case .days:
            let rows = max(5, gridData.days.count / 7)
            return rows == 6 ? 266 : 224
        case .months, .years:
            return 224
        }
    }
    
    @State private var appearScale: CGFloat = 0.95
    @State private var appearOpacity: Double = 0.0
    
    // Cached static formatters to avoid expensive allocation per frame
    private static let detailDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M月d日 EEEE"
        return f
    }()
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    var body: some View {
        ZStack {
            mainFlyoutContent
                .offset(x: inspectingEvent != nil ? -50 : 0)
                .opacity(inspectingEvent != nil ? 0.25 : 1.0)
                .disabled(inspectingEvent != nil)
                .compositingGroup()
            
            if let event = inspectingEvent {
                EventDetailView(event: event) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        inspectingEvent = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .compositingGroup()
                .zIndex(1)
            }
        }
        .scaleEffect(appearScale, anchor: .top)
        .opacity(appearOpacity)
        .frame(width: 390, height: 650)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: inspectingEvent != nil)
        .onAppear {
            triggerEntranceAnimation()
            reloadGridData()
            eventService.fetchEvents(for: selectedDate)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CalendarFlyoutWillOpen"))) { _ in
            triggerEntranceAnimation()
        }
        .onChange(of: displayedDate) { _ in
            reloadGridData()
        }
        .onChange(of: startOnMonday) { _ in
            reloadGridData()
        }
        .onChange(of: selectedDate) { newDate in
            eventService.fetchEvents(for: newDate)
        }
    }
    
    private func triggerEntranceAnimation() {
        appearScale = 0.95
        appearOpacity = 0.0
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            appearScale = 1.0
            appearOpacity = 1.0
        }
    }
    
    private func reloadGridData() {
        gridData = CalendarHelper.generateMonthGrid(for: displayedDate, startOnMonday: startOnMonday)
    }
    
    private var mainFlyoutContent: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            headerBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            
            Divider()
                .opacity(0.3)
            
            // Central Content Area based on mode
            Group {
                switch viewMode {
                case .days:
                    daysView
                case .months:
                    monthsPickerView
                case .years:
                    yearsPickerView
                }
            }
            .frame(height: calendarContentHeight)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: calendarContentHeight)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.3)
            
            // Bottom Day Details / Events Card (Windows Flyout style)
            dayDetailsCard
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Spacer(minLength: 0)
            
            Divider()
                .opacity(0.2)
            
            // Action Toolbar
            bottomToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 8) {
            Button(action: toggleViewMode) {
                HStack(spacing: 4) {
                    Text(headerTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(viewMode == .days ? 0 : 180))
                }
            }
            .buttonStyle(.plain)
            
            if !isViewingCurrentMonth {
                Button(action: jumpToToday) {
                    Text("今日")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CalendarTheme.winBlue.opacity(0.18))
                        .foregroundColor(CalendarTheme.winBlue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Button(action: navigatePrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Button(action: navigateNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var headerTitle: String {
        let cal = Calendar.current
        let year = cal.component(.year, from: displayedDate)
        switch viewMode {
        case .days:
            return gridData.monthTitle
        case .months:
            return "\(year)年"
        case .years:
            let startYear = (year / 10) * 10
            return "\(startYear) - \(startYear + 9)"
        }
    }
    
    private var isViewingCurrentMonth: Bool {
        let cal = Calendar.current
        return cal.isDate(displayedDate, equalTo: Date(), toGranularity: .month)
    }
    
    // MARK: - Days View
    private var daysView: some View {
        VStack(spacing: 4) {
            // Weekday symbols
            HStack(spacing: 0) {
                ForEach(gridData.weekdayHeaders, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            
            // 7x5 or 7x6 Grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(gridData.days) { day in
                    let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                    DayCellView(
                        day: day,
                        isSelected: isSelected,
                        showLunar: showLunar,
                        animationNamespace: calendarAnimation,
                        onSelect: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedDate = day.date
                                if !day.isCurrentMonth {
                                    displayedDate = day.date
                                }
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Months Picker (Zoom View)
    private var monthsPickerView: some View {
        let months = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        let currentMonth = Calendar.current.component(.month, from: displayedDate)
        
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(1...12, id: \.self) { m in
                Button(action: {
                    if let newDate = Calendar.current.date(bySetting: .month, value: m, of: displayedDate) {
                        displayedDate = newDate
                        viewMode = .days
                    }
                }) {
                    Text(months[m - 1])
                        .font(.system(size: 13, weight: m == currentMonth ? .bold : .regular))
                        .foregroundColor(m == currentMonth ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(m == currentMonth ? CalendarTheme.winBlue : Color.primary.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Years Picker (Zoom View)
    private var yearsPickerView: some View {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: displayedDate)
        let startYear = (currentYear / 10) * 10
        let years = Array(startYear...(startYear + 9))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(years, id: \.self) { y in
                Button(action: {
                    if let newDate = Calendar.current.date(bySetting: .year, value: y, of: displayedDate) {
                        displayedDate = newDate
                        viewMode = .months
                    }
                }) {
                    Text("\(y)")
                        .font(.system(size: 13, weight: y == currentYear ? .bold : .regular))
                        .foregroundColor(y == currentYear ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(y == currentYear ? CalendarTheme.winBlue : Color.primary.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Bottom Day Details / Events Card
    private var dayDetailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Date & Count
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.detailDateFormatter.string(from: selectedDate))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    
                    let lunar = CalendarHelper.lunarInfo(for: selectedDate)
                    if !lunar.lunar.isEmpty {
                        HStack(spacing: 4) {
                            Text("农历 \(lunar.lunar)")
                                .font(.system(size: 12))
                                .foregroundColor(.primary.opacity(0.75))
                            if let fest = lunar.festival {
                                Text(fest)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(CalendarTheme.festivalText.opacity(0.18))
                                    .foregroundColor(CalendarTheme.festivalText)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                
                Spacer()
                
                if eventService.isAuthorized && !eventService.eventsForSelectedDate.isEmpty {
                    Text("\(eventService.eventsForSelectedDate.count) 项日程")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CalendarTheme.winBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CalendarTheme.winBlue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .id(Calendar.current.startOfDay(for: selectedDate))
            .transition(.opacity)
            
            // Events List or Prompt
            if !eventService.isAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(CalendarTheme.winBlue)
                    Text(eventService.authorizationStatus == .denied ? "日历未授权，请在设置中开启" : "点击同步系统日历日程")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(eventService.authorizationStatus == .denied ? "前往设置" : "授权") {
                        Task {
                            await eventService.requestAccess()
                            eventService.fetchEvents(for: selectedDate)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            } else if eventService.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取日程…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 90)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
            } else if eventService.eventsForSelectedDate.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("暂无日程安排")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 90)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(eventService.eventsForSelectedDate) { item in
                            Button(action: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    inspectingEvent = item
                                }
                            }) {
                                HStack(alignment: .center, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: item.calendarColor) ?? CalendarTheme.winBlue)
                                        .frame(width: 4, height: 38)
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                        
                                        HStack(spacing: 8) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock")
                                                    .font(.system(size: 10))
                                                if item.isAllDay {
                                                    Text("全天")
                                                } else {
                                                    Text("\(Self.timeFormatter.string(from: item.startDate)) - \(Self.timeFormatter.string(from: item.endDate))")
                                                }
                                            }
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            
                                            if let loc = item.location, !loc.isEmpty {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "mappin.and.ellipse")
                                                        .font(.system(size: 10))
                                                    Text(loc)
                                                        .lineLimit(1)
                                                }
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .id(Calendar.current.startOfDay(for: selectedDate))
                .transition(.opacity)
                .frame(minHeight: 140, maxHeight: 210)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedDate)
    }
    
    // MARK: - Bottom Toolbar
    private var bottomToolbar: some View {
        HStack {
            Button(action: {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                    NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
            }) {
                Label("打开日历", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if let onPin = onPinToDesktop {
                Button(action: onPin) {
                    Label("固定至桌面", systemImage: "pin")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let onSettings = onOpenSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Actions
    private func toggleViewMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch viewMode {
            case .days:
                viewMode = .months
            case .months:
                viewMode = .years
            case .years:
                viewMode = .days
            }
        }
    }
    
    private func jumpToToday() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            displayedDate = Date()
            selectedDate = Date()
            viewMode = .days
        }
    }
    
    private func navigatePrevious() {
        let cal = Calendar.current
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch viewMode {
            case .days:
                if let prev = cal.date(byAdding: .month, value: -1, to: displayedDate) {
                    displayedDate = prev
                }
            case .months:
                if let prev = cal.date(byAdding: .year, value: -1, to: displayedDate) {
                    displayedDate = prev
                }
            case .years:
                if let prev = cal.date(byAdding: .year, value: -10, to: displayedDate) {
                    displayedDate = prev
                }
            }
        }
    }
    
    private func navigateNext() {
        let cal = Calendar.current
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch viewMode {
            case .days:
                if let next = cal.date(byAdding: .month, value: 1, to: displayedDate) {
                    displayedDate = next
                }
            case .months:
                if let next = cal.date(byAdding: .year, value: 1, to: displayedDate) {
                    displayedDate = next
                }
            case .years:
                if let next = cal.date(byAdding: .year, value: 10, to: displayedDate) {
                    displayedDate = next
                }
            }
        }
    }
}

// MARK: - Extracted High-Performance DayCellView
struct DayCellView: View {
    let day: CalendarDay
    let isSelected: Bool
    let showLunar: Bool
    let animationNamespace: Namespace.ID
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 1) {
                ZStack {
                    if day.isToday {
                        Circle()
                            .fill(CalendarTheme.winBlue)
                            .frame(width: 24, height: 24)
                    }
                    
                    Text("\(day.dayNumber)")
                        .font(.system(size: 12.5, weight: day.isToday ? .bold : (isSelected ? .semibold : .regular)))
                        .foregroundColor(cellTextColor)
                }
                
                if showLunar {
                    Text(day.lunarText)
                        .font(.system(size: 9, weight: day.festivalText != nil ? .medium : .regular))
                        .foregroundColor(lunarTextColor)
                        .lineLimit(1)
                }
            }
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(day.isToday ? CalendarTheme.winBlue.opacity(0.12) : CalendarTheme.winSelected)
                            .matchedGeometryEffect(id: "selectedDayHighlight", in: animationNamespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(CalendarTheme.winHover)
                    }
                }
            )
            .overlay(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CalendarTheme.winBlue, lineWidth: 1.5)
                            .matchedGeometryEffect(id: "selectedDayBorder", in: animationNamespace)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var cellTextColor: Color {
        if day.isToday {
            return .white
        } else if day.isCurrentMonth {
            return .primary
        } else {
            return CalendarTheme.overflowText
        }
    }
    
    private var lunarTextColor: Color {
        if !day.isCurrentMonth {
            return CalendarTheme.overflowLunarText
        }
        if day.festivalText != nil {
            return CalendarTheme.festivalText
        }
        if day.isToday {
            return CalendarTheme.winBlue
        }
        return CalendarTheme.lunarText
    }
}

// Visual Effect View for Native macOS Translucent Material (Windows Acrylic style)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
