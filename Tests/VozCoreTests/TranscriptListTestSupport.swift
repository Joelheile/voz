import Foundation

let listCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}()

let listNow = listDate(day: 22, hour: 15)

func listDate(day: Int, hour: Int, minute: Int = 0, year: Int = 2026) -> Date {
    listCalendar.date(from: DateComponents(year: year, month: 10, day: day, hour: hour, minute: minute))!
}

func listDate(secondsBeforeNow seconds: Double) -> Date {
    listNow.addingTimeInterval(-seconds)
}
