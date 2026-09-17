import Foundation
import SwiftUI
import Combine
import Security

class JarviManager: ObservableObject {
    static let shared = JarviManager()
    
    @Published var isLinked: Bool = false
    @Published var availableTodoLists: [JarviTodoList] = []
    @Published var availableCalendars: [JarviCalendar] = []
    @Published var latestTodoItems: [JarviTodoItem] = []
    @Published var jarviToken: String = "" {
        didSet {
            isLinked = !jarviToken.isEmpty
            saveTokenToKeychain(jarviToken)
            DispatchQueue.main.async {
                // New credentials, clean slate — the next fetch re-evaluates.
                self.authErrorMessage = nil
                if self.isLinked {
                    self.startCommandPolling()
                } else {
                    self.stopCommandPolling()
                }
                self.fetchTodoLists()
                self.fetchCalendars()
                NotificationCenter.default.post(name: Notification.Name("JarviTokenChanged"), object: nil)
            }
        }
    }
    // Empty until pairing supplies the real identity. Never default this to a
    // real ID — a hardcoded fallback silently routed unpaired installs onto the
    // wrong Jarvi account.
    @Published var jarviUserId: String = "" {
        didSet {
            UserDefaults.standard.set(jarviUserId, forKey: "jarvi_user_id")
            if isLinked {
                DispatchQueue.main.async {
                    self.fetchTodoLists()
                    self.fetchCalendars()
                }
            }
        }
    }
    /// Email of the paired Jarvi account, when the pairing response provides it.
    /// Shown in Settings so the user can always see which account is linked.
    @Published var jarviUserEmail: String = "" {
        didSet { UserDefaults.standard.set(jarviUserEmail, forKey: "jarvi_user_email") }
    }
    /// Set when the server rejects our credentials (401/403) on a data fetch.
    /// A non-empty token is not proof of a working session — the backend can
    /// deprecate a token format after pairing, leaving the app "linked" but
    /// unable to pull anything.
    @Published var authErrorMessage: String? = nil
    
    private let baseURL = "https://asifthatworks.com/api/v1"
    private let keychainService = "com.fatcat.jarvi"

    private var deviceId: String {
        if let stored = UserDefaults.standard.string(forKey: "jarvi_device_id") { return stored }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "jarvi_device_id")
        return newId
    }

    // MARK: - Command Polling

    struct JarviCommand: Codable {
        let id: String
        let type: String
        let title: String?
        let workDurationMins: Int?
        let breakDurationMins: Int?
        let ageSeconds: Double?
    }

    private struct PendingCommandsResponse: Codable {
        let success: Bool?
        let commands: [JarviCommand]
    }

    private var commandPollTimer: Timer?

    func startCommandPolling() {
        guard commandPollTimer == nil else { return }
        commandPollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.fetchPendingCommands()
        }
        commandPollTimer?.tolerance = 1.0
        fetchPendingCommands()
    }

    func stopCommandPolling() {
        commandPollTimer?.invalidate()
        commandPollTimer = nil
    }

    private func fetchPendingCommands() {
        guard isLinked, !jarviToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/fatcat/pending-command") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthHeaders(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            guard let parsed = try? JSONDecoder().decode(PendingCommandsResponse.self, from: data) else { return }

            for command in parsed.commands {
                guard command.type == "START_POMODORO" else { continue }
                guard (command.ageSeconds ?? 0) <= 90 else { continue }

                DispatchQueue.main.async {
                    var userInfo: [String: Any] = [
                        "title": command.title ?? "",
                        "workDurationMins": command.workDurationMins ?? 25,
                    ]
                    if let breakMins = command.breakDurationMins {
                        userInfo["breakDurationMins"] = breakMins
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name("JarviStartPomodoro"),
                        object: nil,
                        userInfo: userInfo
                    )
                }
            }
        }.resume()
    }

    func sendFatcatEvent(_ event: String, title: String = "", workDurationMins: Int = 0, breakDurationMins: Int = 0) {
        guard isLinked, !jarviToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/fatcat/event") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request)

        var payload: [String: Any] = ["event": event, "platform": "macos"]
        if !title.isEmpty { payload["title"] = title }
        if workDurationMins > 0 { payload["workDurationMins"] = workDurationMins }
        if breakDurationMins > 0 { payload["breakDurationMins"] = breakDurationMins }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { _, response, _ in
                if let httpResp = response as? HTTPURLResponse {
                    print("Jarvi fatcat event [\(event)]: \(httpResp.statusCode)")
                }
            }.resume()
        } catch {}
    }
    
    private init() {
        if let savedUserId = UserDefaults.standard.string(forKey: "jarvi_user_id"), !savedUserId.isEmpty {
            self.jarviUserId = savedUserId
        }
        if let savedEmail = UserDefaults.standard.string(forKey: "jarvi_user_email"), !savedEmail.isEmpty {
            self.jarviUserEmail = savedEmail
        }
        if let savedToken = loadTokenFromKeychain() {
            self.jarviToken = savedToken
            self.isLinked = !savedToken.isEmpty
            if !savedToken.isEmpty {
                DispatchQueue.main.async {
                    self.startCommandPolling()
                    self.fetchTodoLists()
                    self.fetchCalendars()
                }
            }
        }
    }
    
    private func applyAuthHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(jarviToken)", forHTTPHeaderField: "Authorization")
        request.setValue(jarviToken, forHTTPHeaderField: "X-API-Key")
        // Only claim an identity we actually have — an empty X-User-ID must fail
        // server-side rather than silently resolve to someone else's account.
        if !jarviUserId.isEmpty {
            request.setValue(jarviUserId, forHTTPHeaderField: "X-User-ID")
        }
    }

    /// Pull the unique account id out of a server response. Only the canonical
    /// web-account id counts — messenger ids (Telegram/WhatsApp/Messenger/
    /// Instagram) are channels hanging off that account and are never accepted
    /// as identity. Bare "id" is deliberately excluded — in pairing responses
    /// it can name the pairing record rather than the account.
    static func extractAccountId(from json: [String: Any]) -> String? {
        let idKeys = ["userId", "user_id", "accountId", "account_id", "webId", "web_id"]
        for key in idKeys {
            if let str = json[key] as? String, !str.isEmpty { return str }
            if let int = json[key] as? Int { return "\(int)" }
        }
        return nil
    }

    /// Record whether the server accepted our credentials on a data fetch.
    /// Prefers the server's own message (e.g. "This pairing token format is
    /// deprecated…") so the user sees the real reason, not a generic failure.
    private func recordAuthResult(response: URLResponse?, data: Data?) {
        guard let http = response as? HTTPURLResponse else { return }
        DispatchQueue.main.async {
            if http.statusCode == 401 || http.statusCode == 403 {
                var message = "Session rejected by server — please disconnect and re-pair"
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let serverMsg = json["message"] as? String ?? json["error"] as? String,
                   !serverMsg.isEmpty {
                    message = serverMsg
                }
                self.authErrorMessage = message
            } else if (200...299).contains(http.statusCode) {
                self.authErrorMessage = nil
            }
        }
    }
    
    private func saveTokenToKeychain(_ token: String) {
        let data = token.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)
        
        if !token.isEmpty {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecValueData as String: data
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
    
    private func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &dataTypeRef) == errSecSuccess,
           let data = dataTypeRef as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        // One-time migration from old "com.islandbar.jarvi" keychain entry
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.islandbar.jarvi",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var legacyRef: AnyObject?
        if SecItemCopyMatching(legacyQuery as CFDictionary, &legacyRef) == errSecSuccess,
           let data = legacyRef as? Data,
           let token = String(data: data, encoding: .utf8), !token.isEmpty {
            saveTokenToKeychain(token) // write under new service key
            SecItemDelete(legacyQuery as CFDictionary) // remove old entry
            return token
        }
        return nil
    }
    
    func initiatePairing() {
        if let url = URL(string: "https://asifthatworks.com/connect?app=fatcat") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func manualLink(token: String) {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty {
            notifyConnection(token: cleanToken)
        }
    }
    
    func pairWithPin(_ pin: String, completion: @escaping (Bool, String?) -> Void) {
        let cleanPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPin.count == 6 else {
            completion(false, "PIN must be 6 digits")
            return
        }
        
        guard let url = URL(string: "\(baseURL)/fatcat/pair") else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let payload: [String: Any] = [
            "pin": cleanPin,
            "platform": "macos",
            "deviceId": deviceId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, error.localizedDescription)
                        return
                    }
                    guard let data = data else {
                        completion(false, "No response data")
                        return
                    }
                    
                    if let rawStr = String(data: data, encoding: .utf8) {
                        print("Jarvi PIN Pair Response: \(rawStr)")
                    }
                    
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let token = json["token"] as? String ?? json["jarviToken"] as? String ?? json["apiKey"] as? String {
                            // Identity is the canonical web-account id, full
                            // stop. If the server only sends a messenger id,
                            // we store no identity and the panel flags it.
                            if let userId = JarviManager.extractAccountId(from: json) {
                                self?.jarviUserId = userId
                            }
                            if let email = json["email"] as? String ?? json["userEmail"] as? String {
                                self?.jarviUserEmail = email
                            }
                            self?.jarviToken = token
                            completion(true, nil)
                            return
                        } else if let errorMsg = json["error"] as? String ?? json["message"] as? String {
                            completion(false, errorMsg)
                            return
                        }
                    } else if let tokenStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !tokenStr.isEmpty, !tokenStr.contains("{") {
                        self?.jarviToken = tokenStr
                        completion(true, nil)
                        return
                    }
                    
                    if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                        completion(false, "Server returned status \(httpResp.statusCode)")
                        return
                    }
                    
                    completion(false, "Could not verify PIN code")
                }
            }
            task.resume()
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "fatcatpomodoro" else { return }
        
        let host = url.host ?? ""
        let path = url.path
        
        if host == "pair" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            if let tokenItem = components?.queryItems?.first(where: { $0.name == "token" }),
               let token = tokenItem.value {
                notifyConnection(token: token)
            }
        } else if host == "flow" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("JarviRemoteControl"),
                    object: nil,
                    userInfo: ["action": path, "components": components as Any]
                )
            }
        }
    }
    
    func unlink() {
        jarviToken = ""
        // Clear the identity too — a stale ID left behind here is how the app
        // ends up silently acting as the wrong account after a re-pair.
        jarviUserId = ""
        jarviUserEmail = ""
        authErrorMessage = nil
    }
    
    // MARK: - Todos API
    
    struct JarviTodoItem: Codable {
        let id: String?
        let title: String?
        let task: String?
        let name: String?
        let completed: Bool?
        let list: String?
        let list_id: String?
        let category: String?
        let project: String?
    }
    
    struct JarviTodoResponse: Codable {
        let todos: [JarviTodoItem]?
        let tasks: [JarviTodoItem]?
        let items: [JarviTodoItem]?
    }
    
    struct JarviTodoList: Codable, Identifiable, Equatable {
        let id: String
        let name: String
    }
    
    struct JarviCalendar: Codable, Identifiable, Equatable {
        let id: String
        let title: String
    }
    
    func fetchCalendars() {
        guard isLinked, !jarviToken.isEmpty else { return }
        let endpointString = "\(baseURL)/fatcat/calendars"
        guard let url = URL(string: endpointString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthHeaders(to: &request)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Jarvi fetchCalendars Error: \(error.localizedDescription)")
                return
            }
            self.recordAuthResult(response: response, data: data)
            if let httpResp = response as? HTTPURLResponse {
                print("Jarvi fetchCalendars Status: \(httpResp.statusCode)")
            }
            guard let data = data else { return }
            
            var cals: [JarviCalendar] = []
            if let items = try? JSONDecoder().decode([JarviCalendar].self, from: data) {
                cals = items
            } else if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let array = json["calendars"] as? [[String: Any]] ?? json["items"] as? [[String: Any]] ?? json["data"] as? [[String: Any]] {
                for item in array {
                    if let id = item["id"] as? String ?? item["calendarId"] as? String,
                       let title = item["title"] as? String ?? item["summary"] as? String ?? item["name"] as? String {
                        cals.append(JarviCalendar(id: id, title: title))
                    }
                }
            } else if let array = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                for item in array {
                    if let id = item["id"] as? String ?? item["calendarId"] as? String,
                       let title = item["title"] as? String ?? item["summary"] as? String ?? item["name"] as? String {
                        cals.append(JarviCalendar(id: id, title: title))
                    }
                }
            }
            DispatchQueue.main.async {
                self.availableCalendars = cals
            }
        }
        task.resume()
    }
    
    func addGoogleCalendarEvent(title: String, startDate: Date, endDate: Date, calendarId: String) {
        guard isLinked, !jarviToken.isEmpty else {
            print("Jarvi Calendar Error: Not linked or token empty when adding event \"\(title)\"")
            return
        }
        let endpointString = "\(baseURL)/fatcat/calendar-events"
        guard let url = URL(string: endpointString) else { return }
        
        let targetCalId = calendarId.isEmpty ? "primary" : calendarId
        print("Jarvi Calendar: Adding event \"\(title)\" to calendar \"\(targetCalId)\" at \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request)
        
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "title": title,
            "summary": title,
            "startDate": formatter.string(from: startDate),
            "endDate": formatter.string(from: endDate),
            "startTime": formatter.string(from: startDate),
            "endTime": formatter.string(from: endDate),
            "calendarId": targetCalId,
            "calendar_id": targetCalId,
            "type": "event",
            "action": "create"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Jarvi Google Calendar Event Error: \(error.localizedDescription)")
                    return
                }
                if let httpResp = response as? HTTPURLResponse {
                    print("Jarvi Google Calendar Event Added: Status \(httpResp.statusCode)")
                    if let data = data, let str = String(data: data, encoding: .utf8) {
                        print("Jarvi Calendar Response: \(str)")
                    }
                }
            }
            task.resume()
        } catch {
            print("Jarvi Google Calendar Payload Error: \(error)")
        }
    }
    
    func createGoogleTask(taskTitle: String, listId: String, completion: ((String?) -> Void)? = nil) {
        guard isLinked, !jarviToken.isEmpty else {
            completion?(nil)
            return
        }
        let endpointString = "\(baseURL)/fatcat/todos"
        guard let url = URL(string: endpointString) else {
            completion?(nil)
            return
        }
        
        let targetListId = listId.isEmpty ? "@default" : listId
        print("Jarvi Task: Creating \"\(taskTitle)\" in list \"\(targetListId)\"")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request)
        
        let payload: [String: Any] = [
            "title": taskTitle,
            "task": taskTitle,
            "name": taskTitle,
            "listId": targetListId,
            "list_id": targetListId,
            "category": targetListId,
            "project": targetListId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Jarvi Google Task Create Error: \(error.localizedDescription)")
                    completion?(nil)
                    return
                }
                if let httpResp = response as? HTTPURLResponse {
                    print("Jarvi Google Task Created: Status \(httpResp.statusCode)")
                    if let data = data, let str = String(data: data, encoding: .utf8) {
                        print("Jarvi Task Create Response: \(str)")
                        if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let id = dict["id"] as? String ?? dict["taskId"] as? String ?? dict["task_id"] as? String {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: Notification.Name("JarviTodosUpdated"), object: nil)
                            }
                            completion?(id)
                            return
                        }
                    }
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("JarviTodosUpdated"), object: nil)
                    }
                }
                completion?(nil)
            }
            task.resume()
        } catch {
            print("Jarvi Google Task Create Payload Error: \(error)")
            completion?(nil)
        }
    }
    
    func completeGoogleTask(taskTitle: String, listId: String, durationMinutes: Int) {
        guard isLinked, !jarviToken.isEmpty else {
            print("Jarvi Task Error: Not linked or token empty when completing task \"\(taskTitle)\"")
            return
        }
        guard let url = URL(string: "\(baseURL)/fatcat/todos/complete") else { return }
        
        let targetListId = listId.isEmpty ? "@default" : listId
        print("Jarvi Task: Completing \"\(taskTitle)\" in list \"\(targetListId)\" (duration: \(durationMinutes)m)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request)
        
        let matchedItem = latestTodoItems.first { item in
            let title = item.title ?? item.task ?? item.name ?? ""
            return title.caseInsensitiveCompare(taskTitle) == .orderedSame
        }
        
        var payload: [String: Any] = [
            "title": taskTitle,
            "listId": targetListId,
            "list_id": targetListId,
            "sessionDurationMinutes": durationMinutes
        ]
        
        if let taskId = matchedItem?.id {
            payload["taskId"] = taskId
            payload["task_id"] = taskId
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Jarvi Google Task Complete Error: \(error.localizedDescription)")
                    return
                }
                if let httpResp = response as? HTTPURLResponse {
                    print("Jarvi Google Task Completed: Status \(httpResp.statusCode)")
                    if let data = data, let str = String(data: data, encoding: .utf8) {
                        print("Jarvi Task Complete Response: \(str)")
                    }
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("JarviTodosUpdated"), object: nil)
                    }
                }
            }
            task.resume()
        } catch {
            print("Jarvi Google Task Payload Error: \(error)")
        }
    }
    
    func fetchTodoLists() {
        guard isLinked, !jarviToken.isEmpty else { return }
        let endpointString = "\(baseURL)/fatcat/todo-lists"
        guard let url = URL(string: endpointString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthHeaders(to: &request)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Jarvi fetchTodoLists Error: \(error.localizedDescription)")
                return
            }
            self.recordAuthResult(response: response, data: data)
            if let httpResp = response as? HTTPURLResponse {
                print("Jarvi fetchTodoLists Status: \(httpResp.statusCode)")
            }
            guard let data = data else { return }
            
            var lists: [JarviTodoList] = []
            if let items = try? JSONDecoder().decode([JarviTodoList].self, from: data) {
                lists = items
            } else if let strings = try? JSONDecoder().decode([String].self, from: data) {
                lists = strings.map { JarviTodoList(id: $0, name: $0) }
            } else if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let array = json["lists"] as? [[String: Any]] ?? json["todoLists"] as? [[String: Any]] ?? json["todo_lists"] as? [[String: Any]] ?? json["categories"] as? [[String: Any]] {
                for item in array {
                    if let id = item["id"] as? String ?? item["name"] as? String,
                       let name = item["title"] as? String ?? item["name"] as? String ?? item["id"] as? String {
                        lists.append(JarviTodoList(id: id, name: name))
                    }
                }
            }
            DispatchQueue.main.async {
                if !lists.isEmpty {
                    self.availableTodoLists = lists
                } else if self.availableTodoLists.isEmpty {
                    self.availableTodoLists = [JarviTodoList(id: "@default", name: "My Google Tasks")]
                }
            }
        }
        task.resume()
    }

    func fetchTodos(list: String = "", completion: @escaping ([String]) -> Void) {
        guard isLinked, !jarviToken.isEmpty else {
            completion([])
            return
        }
        
        let endpointString = "\(baseURL)/fatcat/todos"
        var components = URLComponents(string: endpointString)
        if !list.isEmpty {
            components?.queryItems = [
                URLQueryItem(name: "list", value: list),
                URLQueryItem(name: "list_id", value: list),
                URLQueryItem(name: "category", value: list),
                URLQueryItem(name: "project", value: list)
            ]
        }
        guard let url = components?.url ?? URL(string: endpointString) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthHeaders(to: &request)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Jarvi fetchTodos Error: \(error?.localizedDescription ?? "unknown error")")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            self.recordAuthResult(response: response, data: data)
            if let httpResp = response as? HTTPURLResponse {
                print("Jarvi fetchTodos Status: \(httpResp.statusCode)")
            }
            
            var extractedTitles: [String] = []
            var parsedItems: [JarviTodoItem] = []
            
            let matchesList: (JarviTodoItem) -> Bool = { item in
                if list.isEmpty || list == "@default" { return true }
                if let iList = item.list ?? item.list_id ?? item.category ?? item.project {
                    return iList.caseInsensitiveCompare(list) == .orderedSame
                }
                return true
            }
            
            if let items = try? JSONDecoder().decode([JarviTodoItem].self, from: data) {
                parsedItems = items
                extractedTitles = items.filter { !($0.completed ?? false) && matchesList($0) }.compactMap { $0.title ?? $0.task ?? $0.name }
            }
            else if let strings = try? JSONDecoder().decode([String].self, from: data) {
                extractedTitles = strings
                parsedItems = strings.map { JarviTodoItem(id: nil, title: $0, task: $0, name: $0, completed: false, list: nil, list_id: nil, category: nil, project: nil) }
            }
            else if let resp = try? JSONDecoder().decode(JarviTodoResponse.self, from: data),
                    let items = resp.todos ?? resp.tasks ?? resp.items {
                parsedItems = items
                extractedTitles = items.filter { !($0.completed ?? false) && matchesList($0) }.compactMap { $0.title ?? $0.task ?? $0.name }
            }
            else if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                if let dict = json as? [String: Any] {
                    if let array = dict["tasks"] as? [[String: Any]] ?? dict["todos"] as? [[String: Any]] ?? dict["data"] as? [[String: Any]] {
                        for item in array {
                            if let title = item["title"] as? String ?? item["task"] as? String ?? item["name"] as? String {
                                let id = item["id"] as? String
                                let completed = item["completed"] as? Bool ?? false
                                let status = item["status"] as? String
                                let isDone = completed || (status == "completed")
                                let itemList = item["list"] as? String ?? item["list_id"] as? String ?? item["category"] as? String ?? item["project"] as? String
                                let match = list.isEmpty || list == "@default" || (itemList?.caseInsensitiveCompare(list) == .orderedSame) || (itemList == nil)
                                if !isDone && match {
                                    extractedTitles.append(title)
                                    parsedItems.append(JarviTodoItem(id: id, title: title, task: title, name: title, completed: isDone, list: itemList, list_id: itemList, category: itemList, project: itemList))
                                }
                            }
                        }
                    } else if let strings = dict["todos"] as? [String] ?? dict["tasks"] as? [String] {
                        extractedTitles = strings
                        parsedItems = strings.map { JarviTodoItem(id: nil, title: $0, task: $0, name: $0, completed: false, list: nil, list_id: nil, category: nil, project: nil) }
                    }
                } else if let array = json as? [[String: Any]] {
                    for item in array {
                        if let title = item["title"] as? String ?? item["task"] as? String ?? item["name"] as? String {
                            let id = item["id"] as? String
                            let completed = item["completed"] as? Bool ?? false
                            let status = item["status"] as? String
                            let isDone = completed || (status == "completed")
                            let itemList = item["list"] as? String ?? item["list_id"] as? String ?? item["category"] as? String ?? item["project"] as? String
                            let match = list.isEmpty || list == "@default" || (itemList?.caseInsensitiveCompare(list) == .orderedSame) || (itemList == nil)
                            if !isDone && match {
                                extractedTitles.append(title)
                                parsedItems.append(JarviTodoItem(id: id, title: title, task: title, name: title, completed: isDone, list: itemList, list_id: itemList, category: itemList, project: itemList))
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.latestTodoItems = parsedItems
                completion(extractedTitles)
            }
        }
        task.resume()
    }
    
    // MARK: - API Endpoints
    
    func sendEvent(type: String, sessionId: String, title: String, workMins: Int = 0, breakMins: Int = 0, list: String = "") {
        guard isLinked, !jarviToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/flow/event") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jarviToken)", forHTTPHeaderField: "Authorization")
        
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        
        var payload: [String: Any] = [
            "event": type,
            "sessionId": sessionId,
            "title": title,
            "workDurationMins": workMins,
            "breakDurationMins": breakMins,
            "timestamp": timestamp
        ]
        if !list.isEmpty {
            payload["list"] = list
            payload["category"] = list
            payload["project"] = list
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let task = URLSession.shared.dataTask(with: request) { _, response, _ in
                if let httpResp = response as? HTTPURLResponse {
                    print("Jarvi Event Sent [\(type)]: Status \(httpResp.statusCode)")
                }
            }
            task.resume()
        } catch {}
    }
    
    private func notifyConnection(token: String) {
        guard let url = URL(string: "\(baseURL)/squatalarm/connect-device") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let hostName = Host.current().localizedName ?? "Mac"
        let payload: [String: String] = [
            "token": token,
            "app": "FatCatPomodoroIsland (macOS)",
            "platform": "macos",
            "deviceName": hostName
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                        // Capture the account identity from the response too —
                        // identity before token, so the fetches the token
                        // triggers already carry it.
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            if let userId = JarviManager.extractAccountId(from: json) {
                                self.jarviUserId = userId
                            }
                            if let email = json["email"] as? String ?? json["userEmail"] as? String {
                                self.jarviUserEmail = email
                            }
                        }
                        self.jarviToken = token
                        print("Jarvi by AsIfThatWorks: Successfully connected device.")
                    } else {
                        print("Jarvi by AsIfThatWorks: Failed to connect device. HTTP: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                        // Still save the token locally for robustness if desired, but we only mark as paired if successful
                        self.jarviToken = token 
                    }
                }
            }
            task.resume()
        } catch {
            print("Jarvi Connection Payload Error: \(error)")
        }
    }
    
    private var isLoggingSession = false
    
    func logPomodoroSession(durationMinutes: Int, taskName: String, interrupted: Bool) {
        guard isLinked, !jarviToken.isEmpty else { return }
        
        // Debounce to prevent duplicate logs within 5 seconds
        guard !isLoggingSession else {
            print("Jarvi Analytics: Ignored duplicate log request within debounce window")
            return
        }
        isLoggingSession = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.isLoggingSession = false
        }
        
        guard let url = URL(string: "\(baseURL)/analytics/pomodoro/session") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jarviToken)", forHTTPHeaderField: "Authorization")
        
        let formatter = ISO8601DateFormatter()
        let completedAt = formatter.string(from: Date())
        
        let payload: [String: Any] = [
            "sessionDurationMinutes": durationMinutes,
            "focusTaskName": taskName.isEmpty ? "FatCatFlow Session" : taskName,
            "sessionType": "FLOW",
            "interrupted": interrupted,
            "completedAt": completedAt,
            "platform": "macos"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Jarvi Analytics Error: \(error)")
                    return
                }
                if let httpResp = response as? HTTPURLResponse {
                    print("Jarvi Analytics Sent: Status \(httpResp.statusCode)")
                }
            }
            task.resume()
        } catch {
            print("Jarvi Analytics Payload Error: \(error)")
        }
    }
}
