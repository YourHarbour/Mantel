import Foundation
import EventKit
import Combine
import AppKit

public struct CalendarEventItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let calendarColor: String
    public let location: String?
    public let calendarTitle: String
    public let notes: String?
    public let url: URL?
    public let attendees: [String]
    public let hasAlarms: Bool
    
    public init(event: EKEvent) {
        self.id = event.eventIdentifier ?? UUID().uuidString
        self.title = event.title ?? "无标题日程"
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.location = event.location
        self.calendarTitle = event.calendar?.title ?? "日历"
        self.notes = event.notes
        self.url = event.url
        self.attendees = event.attendees?.compactMap { $0.name ?? $0.url.absoluteString } ?? []
        self.hasAlarms = event.hasAlarms
        if let cgColor = event.calendar?.cgColor, let color = cgColor.components {
            if color.count >= 3 {
                self.calendarColor = String(format: "#%02lX%02lX%02lX",
                                            lroundf(Float(color[0] * 255)),
                                            lroundf(Float(color[1] * 255)),
                                            lroundf(Float(color[2] * 255)))
            } else {
                self.calendarColor = "#0078D7"
            }
        } else {
            self.calendarColor = "#0078D7"
        }
    }
}

/// EventKit's event query is synchronous and cannot be interrupted once it has entered
/// `events(matching:)`. Running the work through a serial operation queue guarantees that rapid
/// date changes never fan out into concurrent EventKit queries. Cancelling an operation prevents
/// queued work from starting and prevents an in-flight query from publishing stale results.
private final class EventQueryOperation: Operation, @unchecked Sendable {
    private let store: EKEventStore
    private let startDate: Date
    private let endDate: Date
    private let completion: ([CalendarEventItem]) -> Void

    init(store: EKEventStore, startDate: Date, endDate: Date,
         completion: @escaping ([CalendarEventItem]) -> Void) {
        self.store = store
        self.startDate = startDate
        self.endDate = endDate
        self.completion = completion
    }

    override func main() {
        guard !isCancelled else { return }
        let items: [CalendarEventItem] = autoreleasepool {
            let predicate = store.predicateForEvents(
                withStart: startDate, end: endDate, calendars: nil)
            guard !isCancelled else { return [] }
            return store.events(matching: predicate).map(CalendarEventItem.init(event:))
        }
        guard !isCancelled else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.completion(items)
        }
    }
}

@MainActor
public final class EventService: ObservableObject {
    public static let shared = EventService()

    private struct CacheEntry {
        let events: [CalendarEventItem]
        let storedAt: Date
    }
    
    private var eventStore = EKEventStore()
    @Published public var isAuthorized: Bool = false
    @Published public var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published public var eventsForSelectedDate: [CalendarEventItem] = []
    @Published public private(set) var isLoading: Bool = false
    
    private var eventsCache: [Date: CacheEntry] = [:]
    private var cacheOrder: [Date] = []
    private let cacheCapacity = 31
    private let cacheTTL: TimeInterval = 5 * 60

    private let queryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.local.mantel.calendar.event-query"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var fetchOperation: EventQueryOperation?
    private var fetchGeneration: UInt = 0
    private var selectedDate: Date?
    private var selectedDay: Date?
    private var fetchingDay: Date?
    
    public init() {
        checkAuthorization()
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let date = self.selectedDate
                self.cancelFetch(clearResults: true)
                self.clearCache()
                self.checkAuthorization()
                if self.isAuthorized, let date {
                    self.fetchEvents(for: date)
                }
            }
        }
    }
    
    public func clearCache() {
        eventsCache.removeAll()
        cacheOrder.removeAll()
    }

    private func cancelFetch(clearResults: Bool) {
        fetchGeneration &+= 1
        fetchOperation?.cancel()
        fetchOperation = nil
        fetchingDay = nil
        isLoading = false
        if clearResults { eventsForSelectedDate = [] }
    }

    private func cachedEvents(for day: Date, now: Date = Date()) -> [CalendarEventItem]? {
        guard let entry = eventsCache[day] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) <= cacheTTL else {
            eventsCache.removeValue(forKey: day)
            cacheOrder.removeAll { $0 == day }
            return nil
        }
        cacheOrder.removeAll { $0 == day }
        cacheOrder.append(day)
        return entry.events
    }

    private func storeInCache(_ events: [CalendarEventItem], for day: Date) {
        eventsCache[day] = CacheEntry(events: events, storedAt: Date())
        cacheOrder.removeAll { $0 == day }
        cacheOrder.append(day)
        while cacheOrder.count > cacheCapacity {
            eventsCache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }
    
    public func checkAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        self.authorizationStatus = status
        if #available(macOS 14.0, *) {
            self.isAuthorized = (status == .fullAccess)
        } else {
            self.isAuthorized = (status == .authorized)
        }
    }
    
    public func requestAccess() async {
        checkAuthorization()
        
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            cancelFetch(clearResults: true)
            // If previously denied, open macOS System Settings directly to Privacy > Calendars
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        let store = EKEventStore()
        do {
            cancelFetch(clearResults: true)
            if #available(macOS 14.0, *) {
                let granted = try await store.requestFullAccessToEvents()
                self.eventStore = store
                self.isAuthorized = granted
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            } else {
                let granted = try await store.requestAccess(to: .event)
                self.eventStore = store
                self.isAuthorized = granted
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            }
            clearCache()
        } catch {
            print("Error requesting calendar authorization: \(error)")
            cancelFetch(clearResults: true)
            self.isAuthorized = false
            self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }
    
    public func fetchEvents(for date: Date) {
        checkAuthorization()
        guard isAuthorized else {
            cancelFetch(clearResults: true)
            return
        }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        selectedDate = date
        selectedDay = startOfDay
        
        // A fresh cache entry is authoritative for a short period, so reopening the popover does
        // not immediately issue the same EventKit query again.
        if let cached = cachedEvents(for: startOfDay) {
            cancelFetch(clearResults: false)
            eventsForSelectedDate = cached
            return
        }

        // Do not briefly show events belonging to the previously selected day.
        eventsForSelectedDate = []
        guard fetchingDay != startOfDay else { return }
        
        fetchOperation?.cancel()
        fetchOperation = nil
        fetchGeneration &+= 1
        let generation = fetchGeneration
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            fetchingDay = nil
            isLoading = false
            return
        }
        fetchingDay = startOfDay
        isLoading = true

        let store = self.eventStore
        let operation = EventQueryOperation(
            store: store,
            startDate: startOfDay,
            endDate: endOfDay
        ) { [weak self] items in
            guard let self,
                  self.fetchGeneration == generation,
                  self.selectedDay == startOfDay,
                  self.fetchingDay == startOfDay else { return }
            self.storeInCache(items, for: startOfDay)
            self.eventsForSelectedDate = items
            self.fetchOperation = nil
            self.fetchingDay = nil
            self.isLoading = false
        }
        fetchOperation = operation
        queryQueue.addOperation(operation)
    }
}
