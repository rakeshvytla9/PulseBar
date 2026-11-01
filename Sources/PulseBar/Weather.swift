import Foundation

struct WeatherDay: Identifiable {
    let id: String
    let high: Double, low: Double, rain: Double
}
struct Forecast {
    let city: String, country: String
    let temperature: Double, wind: Double, humidity: Double
    let days: [WeatherDay]
}
@MainActor final class Weather: ObservableObject {
    @Published var city = ""
    @Published var forecast: Forecast?
    @Published var busy = false
    @Published var error: String?
    func fetch() {
        let query = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                geo.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "en")]
                let (geoData, _) = try await URLSession.shared.data(from: geo.url!)
                let locations = try JSONDecoder().decode(Locations.self, from: geoData)
                guard let place = locations.results?.first else { error = "City not found. Try a nearby larger city."; return }
                var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                url.queryItems = [
                    .init(name: "latitude", value: String(place.latitude)), .init(name: "longitude", value: String(place.longitude)),
                    .init(name: "current", value: "temperature_2m,relative_humidity_2m,wind_speed_10m"),
                    .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
                    .init(name: "forecast_days", value: "5"), .init(name: "timezone", value: "auto")
                ]
                let (data, _) = try await URLSession.shared.data(from: url.url!)
                let value = try JSONDecoder().decode(Response.self, from: data)
                let count = [value.daily.time.count, value.daily.temperature_2m_max.count, value.daily.temperature_2m_min.count, value.daily.precipitation_probability_max.count].min() ?? 0
                forecast = Forecast(city: place.name, country: place.country ?? "", temperature: value.current.temperature_2m,
                                    wind: value.current.wind_speed_10m, humidity: value.current.relative_humidity_2m,
                                    days: (0..<count).map { WeatherDay(id: value.daily.time[$0], high: value.daily.temperature_2m_max[$0], low: value.daily.temperature_2m_min[$0], rain: value.daily.precipitation_probability_max[$0]) })
            } catch { self.error = "Could not load weather: \(error.localizedDescription)" }
        }
    }
    private struct Locations: Decodable {
        struct Place: Decodable { let name: String, country: String?; let latitude: Double, longitude: Double }
        let results: [Place]?
    }
    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double, relative_humidity_2m: Double, wind_speed_10m: Double }
        struct Daily: Decodable { let time: [String]; let temperature_2m_max: [Double], temperature_2m_min: [Double], precipitation_probability_max: [Double] }
        let current: Current, daily: Daily
    }
}
