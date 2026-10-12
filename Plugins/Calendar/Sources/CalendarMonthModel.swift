import Foundation

public struct CalendarDay: Identifiable, Hashable {
    public let id: String
    public let date: Date
    public let dayNumber: Int
    public let isCurrentMonth: Bool
    public let isToday: Bool
    public let lunarText: String
    public let festivalText: String?
    
    public init(
        date: Date,
        dayNumber: Int,
        isCurrentMonth: Bool,
        isToday: Bool,
        lunarText: String = "",
        festivalText: String? = nil
    ) {
        self.id = "\(date.timeIntervalSince1970)_\(dayNumber)_\(isCurrentMonth)"
        self.date = date
        self.dayNumber = dayNumber
        self.isCurrentMonth = isCurrentMonth
        self.isToday = isToday
        self.lunarText = lunarText
        self.festivalText = festivalText
    }
}

public struct MonthGridData {
    public let targetDate: Date
    public let year: Int
    public let month: Int
    public let monthTitle: String
    public let weekdayHeaders: [String]
    public let days: [CalendarDay]
    
    public init(
        targetDate: Date,
        year: Int,
        month: Int,
        monthTitle: String,
        weekdayHeaders: [String],
        days: [CalendarDay]
    ) {
        self.targetDate = targetDate
        self.year = year
        self.month = month
        self.monthTitle = monthTitle
        self.weekdayHeaders = weekdayHeaders
        self.days = days
    }
}

public enum CalendarHelper {
    public static let chineseCalendar = Calendar(identifier: .chinese)
    public static let gregorian = Calendar(identifier: .gregorian)
    
    // Solar Festivals: Month-Day
    private static let solarFestivals: [String: String] = [
        "1-1": "元旦",
        "2-14": "情人节",
        "3-8": "妇女节",
        "4-1": "愚人节",
        "5-1": "劳动节",
        "5-4": "青年节",
        "6-1": "儿童节",
        "7-1": "建党节",
        "8-1": "建军节",
        "9-10": "教师节",
        "10-1": "国庆节",
        "12-25": "圣诞节"
    ]
    
    // Lunar Festivals: Month-Day
    private static let lunarFestivals: [String: String] = [
        "1-1": "春节",
        "1-15": "元宵",
        "2-2": "龙头",
        "5-5": "端午",
        "7-7": "七夕",
        "7-15": "中元",
        "8-15": "中秋",
        "9-9": "重阳",
        "12-8": "腊八",
        "12-23": "小年"
    ]
    
    private static let lock = NSLock()
    private static var monthGridCache: [String: MonthGridData] = [:]
    private static var monthGridOrder: [String] = []
    private static let monthGridCapacity = 24
    
    private static var lunarInfoCache: [String: (lunar: String, festival: String?)] = [:]
    private static var lunarInfoOrder: [String] = []
    private static let lunarInfoCapacity = 365
    
    public static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        monthGridCache.removeAll()
        monthGridOrder.removeAll()
        lunarInfoCache.removeAll()
        lunarInfoOrder.removeAll()
    }
    
    public static func invalidateTodayDependentCache() {
        lock.lock()
        defer { lock.unlock() }
        monthGridCache.removeAll()
        monthGridOrder.removeAll()
    }
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()
    
    public static func targetDate(forMonthOffset offset: Int, baseDate: Date = Date()) -> Date {
        if offset == 0 { return baseDate }
        return gregorian.date(byAdding: .month, value: offset, to: baseDate) ?? baseDate
    }
    
    public static func generateMonthGrid(
        for targetDate: Date,
        startOnMonday: Bool = false
    ) -> MonthGridData {
        var cal = gregorian
        cal.firstWeekday = startOnMonday ? 2 : 1
        
        let components = cal.dateComponents([.year, .month], from: targetDate)
        guard let year = components.year, let month = components.month,
              let firstDayOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstDayOfMonth) else {
            return MonthGridData(targetDate: targetDate, year: 2026, month: 1, monthTitle: "", weekdayHeaders: [], days: [])
        }
        
        let cacheKey = "\(year)-\(month)-\(startOnMonday)"
        lock.lock()
        if let cached = monthGridCache[cacheKey] {
            monthGridOrder.removeAll { $0 == cacheKey }
            monthGridOrder.append(cacheKey)
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // Month Title: e.g. "2026年9月"
        let monthTitle = monthTitleFormatter.string(from: firstDayOfMonth)
        
        // Weekday Headers
        let weekdaySymbols = startOnMonday
            ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["日", "一", "二", "三", "四", "五", "六"]
        
        // Calculate leading days from previous month
        let firstWeekday = cal.component(.weekday, from: firstDayOfMonth)
        let leadingDaysCount: Int
        if startOnMonday {
            leadingDaysCount = (firstWeekday + 5) % 7
        } else {
            leadingDaysCount = (firstWeekday - 1) % 7
        }
        
        var days: [CalendarDay] = []
        let today = Date()
        let todayComponents = cal.dateComponents([.year, .month, .day], from: today)
        
        // 1. Previous month trailing days
        if leadingDaysCount > 0, let prevMonth = cal.date(byAdding: .month, value: -1, to: firstDayOfMonth),
           let prevMonthRange = cal.range(of: .day, in: .month, for: prevMonth) {
            let startPrevDay = prevMonthRange.count - leadingDaysCount + 1
            for d in startPrevDay...prevMonthRange.count {
                if let date = cal.date(bySetting: .day, value: d, of: prevMonth) {
                    let isToday = (todayComponents.year == cal.component(.year, from: date) &&
                                   todayComponents.month == cal.component(.month, from: date) &&
                                   todayComponents.day == d)
                    let (lunar, fest) = lunarInfo(for: date)
                    days.append(CalendarDay(
                        date: date,
                        dayNumber: d,
                        isCurrentMonth: false,
                        isToday: isToday,
                        lunarText: lunar,
                        festivalText: fest
                    ))
                }
            }
        }
        
        // 2. Current month days
        for d in 1...range.count {
            if let date = cal.date(bySetting: .day, value: d, of: firstDayOfMonth) {
                let isToday = (todayComponents.year == year &&
                               todayComponents.month == month &&
                               todayComponents.day == d)
                let (lunar, fest) = lunarInfo(for: date)
                days.append(CalendarDay(
                    date: date,
                    dayNumber: d,
                    isCurrentMonth: true,
                    isToday: isToday,
                    lunarText: lunar,
                    festivalText: fest
                ))
            }
        }
        
        // 3. Next month leading days to complete 5 rows (35 cells) or 6 rows if month overflows
        let weeksNeeded = Int(ceil(Double(days.count) / 7.0))
        let totalCells = (weeksNeeded <= 5) ? 35 : 42
        let remaining = totalCells - days.count
        if remaining > 0, let nextMonth = cal.date(byAdding: .month, value: 1, to: firstDayOfMonth) {
            for d in 1...remaining {
                if let date = cal.date(bySetting: .day, value: d, of: nextMonth) {
                    let isToday = (todayComponents.year == cal.component(.year, from: date) &&
                                   todayComponents.month == cal.component(.month, from: date) &&
                                   todayComponents.day == d)
                    let (lunar, fest) = lunarInfo(for: date)
                    days.append(CalendarDay(
                        date: date,
                        dayNumber: d,
                        isCurrentMonth: false,
                        isToday: isToday,
                        lunarText: lunar,
                        festivalText: fest
                    ))
                }
            }
        }
        
        let result = MonthGridData(
            targetDate: targetDate,
            year: year,
            month: month,
            monthTitle: monthTitle,
            weekdayHeaders: weekdaySymbols,
            days: days
        )
        lock.lock()
        monthGridCache[cacheKey] = result
        monthGridOrder.removeAll { $0 == cacheKey }
        monthGridOrder.append(cacheKey)
        while monthGridOrder.count > monthGridCapacity {
            let evicted = monthGridOrder.removeFirst()
            monthGridCache.removeValue(forKey: evicted)
        }
        lock.unlock()
        return result
    }
    
    private static func cacheLunarResult(_ res: (lunar: String, festival: String?), for key: String) -> (lunar: String, festival: String?) {
        lock.lock()
        lunarInfoCache[key] = res
        lunarInfoOrder.removeAll { $0 == key }
        lunarInfoOrder.append(key)
        while lunarInfoOrder.count > lunarInfoCapacity {
            let evicted = lunarInfoOrder.removeFirst()
            lunarInfoCache.removeValue(forKey: evicted)
        }
        lock.unlock()
        return res
    }

    public static func lunarInfo(for date: Date) -> (lunar: String, festival: String?) {
        let cal = gregorian
        let gComp = cal.dateComponents([.year, .month, .day], from: date)
        guard let gYear = gComp.year, let gMonth = gComp.month, let gDay = gComp.day else {
            return ("", nil)
        }
        let dateKey = "\(gYear)-\(gMonth)-\(gDay)"
        lock.lock()
        if let cached = lunarInfoCache[dateKey] {
            lunarInfoOrder.removeAll { $0 == dateKey }
            lunarInfoOrder.append(dateKey)
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // Solar festival check
        if let fest = solarFestivals["\(gMonth)-\(gDay)"] {
            return cacheLunarResult((fest, fest), for: dateKey)
        }
        
        let cComp = chineseCalendar.dateComponents([.year, .month, .day], from: date)
        guard let lMonth = cComp.month, let lDay = cComp.day else {
            return ("", nil)
        }
        
        // Lunar festival check
        if let lFest = lunarFestivals["\(lMonth)-\(lDay)"] {
            return cacheLunarResult((lFest, lFest), for: dateKey)
        }
        
        let dayNames = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        
        let monthNames = [
            "正月", "二月", "三月", "四月", "五月", "六月",
            "七月", "八月", "九月", "十月", "冬月", "腊月"
        ]
        
        let res: (String, String?)
        if lDay == 1 {
            let mName = (lMonth >= 1 && lMonth <= 12) ? monthNames[lMonth - 1] : "\(lMonth)月"
            res = (mName, nil)
        } else if lDay >= 1 && lDay <= dayNames.count {
            res = (dayNames[lDay - 1], nil)
        } else {
            res = ("", nil)
        }
        return cacheLunarResult(res, for: dateKey)
    }
}
