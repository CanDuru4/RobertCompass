import UIKit
import MapKit
import Combine
import FirebaseAuth

/// Displays shared team progress and submits GPS-checked answers to the server.
/// - Note: The client never computes or writes authoritative scores.
/// - Example: `HomeMapViewController(store: sharedStore)`.
@MainActor
final class HomeMapViewController: TaskViewController, MKMapViewDelegate {
    private let store: GameStore
    private let map = MKMapView()
    private let location = LocationManager()
    private let statusLabel = AppUI.label("Loading your courses...")
    private let teamLabel = AppUI.label("Explore together", style: .title2)
    private let timerLabel = AppUI.label(style: .title1)
    private var actions = UIStackView()
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var foreground: NSObjectProtocol?
    private var centeredGame: String?
    private var overviewGame: String?
    private var expiryRefreshID: String?

    /// Inject the store shared by all signed-in tabs.
    /// - Parameter store: Current account's live session store.
    /// - Returns: A map controller.
    /// - Example: `HomeMapViewController(store: store)`.
    init(store: GameStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }

    /// Build the map, actions, live subscriptions, and foreground refresh handler.
    /// - Returns: Nothing.
    /// - Example: Called by UIKit.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        map.delegate = self
        map.showsCompass = true
        map.showsScale = true
        map.heightAnchor.constraint(equalToConstant: 340).isActive = true
        map.layer.cornerRadius = 16
        map.clipsToBounds = true
        actions.axis = .vertical
        actions.spacing = 10
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        timerLabel.accessibilityIdentifier = "Activity timer"
        statusLabel.accessibilityIdentifier = "Activity status"
        AppUI.form([teamLabel, timerLabel, statusLabel, actions, map], in: self)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "location"), primaryAction: UIAction { [weak self] _ in self?.centerOnUser() }),
            UIBarButtonItem(title: "Map type", menu: UIMenu(children: [
                UIAction(title: "Standard") { [weak self] _ in self?.map.mapType = .standard },
                UIAction(title: "Satellite") { [weak self] _ in self?.map.mapType = .hybrid },
            ])),
        ]
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Rules", primaryAction: UIAction { [weak self] _ in self?.showRules() })
        store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.render() }.store(in: &subscriptions)
        foreground = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                expiryRefreshID = nil
                try? await store.refresh()
                render()
            }
        }
        render()
    }

    /// Run a display-only timer while this tab is visible.
    /// - Parameter animated: UIKit transition animation flag.
    /// - Returns: Nothing.
    /// - Example: Called when returning from the leaderboard.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        Task { try? await store.refresh() }
    }

    /// Release timer work while another tab or screen is active.
    /// - Parameter animated: UIKit transition animation flag.
    /// - Returns: Nothing.
    /// - Example: Called when leaving the map.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func render() {
        actions.arrangedSubviews.forEach { actions.removeArrangedSubview($0); $0.removeFromSuperview() }
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        if store.session?.status != "active",
           let course = store.courses.first(where: { $0.id == store.session?.gameId }) ?? store.courses.first,
           overviewGame != course.id {
            let center = CLLocationCoordinate2D(latitude: course.latitude, longitude: course.longitude)
            if CLLocationCoordinate2DIsValid(center) {
                map.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
                overviewGame = course.id
            }
        }
        if let session = store.session {
            teamLabel.text = "\(session.teamName)\n\(session.gameName)"
            let members = session.memberIds.compactMap { session.memberNames[$0] }.joined(separator: ", ")
            statusLabel.text = "\(session.score) points · \(session.completedIds.count)/\(session.checkpointIds.count) checkpoints\n\(members)"
            if session.status == "waiting" && session.isOpen(at: Backend.now) {
                statusLabel.text = "Team code: \(session.joinCode)\n\(members)\nInvite teammates before starting."
                if session.ownerId == Auth.auth().currentUser?.uid {
                    addAction("Start activity") { [weak self] in self?.start(session) }
                }
                addAction("Leave team") { [weak self] in self?.leave(session) }
            } else if session.status == "active" && session.isOpen(at: Backend.now) {
                let points = store.checkpoints.filter { session.checkpointIds.contains($0.id) && !session.completedIds.contains($0.id) }
                map.addAnnotations(points.map(CheckpointAnnotation.init))
                if centeredGame != session.gameId && !points.isEmpty {
                    map.showAnnotations(map.annotations, animated: false)
                    centeredGame = session.gameId
                }
                if session.ownerId == Auth.auth().currentUser?.uid { addAction("End activity") { [weak self] in self?.leave(session) } }
                addAction("Choose checkpoint") { [weak self] in self?.chooseCheckpoint(points) }
            } else {
                statusLabel.text = "Activity \(session.status == "active" || session.status == "waiting" ? "expired" : session.status).\n\(session.score) points · \(session.completedIds.count) checkpoints completed."
                addEntryActions()
            }
        } else {
            teamLabel.text = "Explore together"
            statusLabel.text = store.isLoading ? "Connecting to your account..." : "Create a team or join one with an invite code."
            addEntryActions()
        }
        if let error = store.errorMessage {
            statusLabel.text = error
            addAction("Retry connection") { [weak self] in
                self?.run { await self?.store.connect() }
            }
        }
        tick()
    }

    private func tick() {
        guard let session = store.session, ["waiting", "active"].contains(session.status) else { timerLabel.text = nil; return }
        let seconds = session.remainingSeconds(at: Backend.now)
        timerLabel.text = session.status == "waiting" ? "Team lobby" : AppUI.duration(seconds)
        if seconds == 0 && expiryRefreshID != session.id {
            expiryRefreshID = session.id
            Task { [weak self] in
                do { try await self?.store.refresh() }
                catch { self?.statusLabel.text = "Time has ended. Reconnect to synchronize your result." }
            }
        }
    }

    private func addAction(_ title: String, action: @escaping () -> Void) {
        actions.addArrangedSubview(AppUI.button(title, action: UIAction { _ in action() }))
    }

    private func addEntryActions() {
        addAction("Create team") { [weak self] in self?.chooseCourse() }
        addAction("Join team") { [weak self] in
            self?.prompt(title: "Join a team", fields: ["12-character team code"]) { values in
                self?.run {
                    let response = try await Backend.call("joinTeam", ["joinCode": values[0]])
                    self?.store.watchSession(response["sessionId"] as? String)
                }
            }
        }
    }

    private func chooseCourse() {
        run { [self] in
            try await store.loadCourses()
            let availableCourses = store.courses.filter { $0.endDate > Backend.now }
            guard !availableCourses.isEmpty else { showMessage("No courses are available yet. Ask the organizer to publish a course."); return }
            let alert = UIAlertController(title: "Choose a course", message: nil, preferredStyle: .actionSheet)
            for course in availableCourses {
                alert.addAction(UIAlertAction(title: course.name, style: .default) { [weak self] _ in self?.createTeam(course) })
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.popoverPresentationController?.sourceView = actions
            present(alert, animated: true)
        }
    }

    private func createTeam(_ course: Course) {
        let fields = course.requiresEntryCode ? ["Team name", "Course entry code"] : ["Team name"]
        prompt(title: "\(course.name)\nUp to \(course.maxTeamSize) players", fields: fields) { [weak self] values in
            self?.run {
                let response = try await Backend.call("createTeam", ["gameId": course.id, "teamName": values[0], "entryCode": values.count > 1 ? values[1] : ""])
                self?.store.watchSession(response["sessionId"] as? String)
            }
        }
    }

    private func start(_ session: GameSession) {
        run { try await Backend.call("startGame", ["sessionId": session.id]) }
    }

    private func leave(_ session: GameSession) {
        let alert = UIAlertController(title: "Leave this activity?", message: session.ownerId == Auth.auth().currentUser?.uid ? "This ends the activity for the whole team. Your recorded progress stays in history." : "You will leave this team lobby.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep playing", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave", style: .destructive) { [weak self] _ in
            self?.run { try await Backend.call("leaveTeam", ["sessionId": session.id]) }
        })
        present(alert, animated: true)
    }

    private func chooseCheckpoint(_ points: [Checkpoint]) {
        guard !points.isEmpty else { showMessage("Checkpoints are loading. Try again shortly."); return }
        let alert = UIAlertController(title: "Remaining checkpoints", message: nil, preferredStyle: .actionSheet)
        points.forEach { point in alert.addAction(UIAlertAction(title: point.name, style: .default) { [weak self] _ in self?.question(point) }) }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = actions
        present(alert, animated: true)
    }

    private func question(_ point: Checkpoint) {
        guard let session = store.session, session.status == "active", session.isOpen(at: Backend.now),
              session.checkpointIds.contains(point.id), !session.completedIds.contains(point.id) else { return }
        let alert = UIAlertController(title: point.name, message: "\(point.question)\n\nBe within \(Int(point.radiusMeters)) meters to answer.", preferredStyle: .alert)
        if point.options.isEmpty {
            alert.addTextField { $0.placeholder = "Your answer"; $0.accessibilityIdentifier = "Your answer" }
            alert.addAction(UIAlertAction(title: "Submit answer", style: .default) { [weak self, weak alert] _ in
                self?.answer(point, sessionId: session.id, value: alert?.textFields?.first?.text ?? "")
            })
        } else {
            for option in point.options {
                alert.addAction(UIAlertAction(title: option, style: .default) { [weak self] _ in self?.answer(point, sessionId: session.id, value: option) })
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func answer(_ point: Checkpoint, sessionId: String, value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showMessage("Enter an answer first."); return }
        run { [self] in
            let fix = try await location.currentLocation()
            let result = try await Backend.call("submitAnswer", ["sessionId": sessionId, "checkpointId": point.id, "answer": value,
                "location": ["latitude": fix.coordinate.latitude, "longitude": fix.coordinate.longitude,
                             "accuracy": fix.horizontalAccuracy, "capturedAt": fix.timestamp.timeIntervalSince1970 * 1000]])
            showMessage(result["duplicate"] as? Bool == true ? "Your team has already completed this checkpoint." : "Correct answer. Your team's score is updated.")
        }
    }

    private func prompt(title: String, fields: [String], action: @escaping ([String]) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        fields.forEach { name in alert.addTextField { $0.placeholder = name; $0.accessibilityIdentifier = name } }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self, weak alert] _ in
            let values = alert?.textFields?.map { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" } ?? []
            guard values.count == fields.count, values.allSatisfy({ !$0.isEmpty }) else {
                self?.showMessage("Complete all fields to continue.")
                return
            }
            action(values)
        })
        present(alert, animated: true)
    }

    private func centerOnUser() {
        run { [self] in
            let fix = try await location.currentLocation()
            map.showsUserLocation = true
            map.setRegion(MKCoordinateRegion(center: fix.coordinate, latitudinalMeters: 500, longitudinalMeters: 500), animated: true)
        }
    }

    private func showRules() {
        let course = store.courses.first { $0.id == store.session?.gameId }
        let controller = RulesViewController(rules: course?.rules)
        navigationController?.pushViewController(controller, animated: true)
    }

    /// Supply reusable checkpoint markers while retaining the system user marker.
    /// - Parameters:
    ///   - mapView: Map requesting a marker.
    ///   - annotation: Checkpoint or system location annotation.
    /// - Returns: A checkpoint marker or nil for system rendering.
    /// - Example: Called by MapKit.
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is CheckpointAnnotation else { return nil }
        let marker = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "checkpoint")
        marker.canShowCallout = true
        marker.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        return marker
    }

    /// Open the exact checkpoint selected by stable identifier, never fuzzy name matching.
    /// - Parameters:
    ///   - mapView: Current map.
    ///   - view: Selected checkpoint marker.
    ///   - control: Callout button tapped by the player.
    /// - Returns: Nothing.
    /// - Example: Called by MapKit after tapping a checkpoint's details.
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        if let annotation = view.annotation as? CheckpointAnnotation { question(annotation.point) }
    }

    deinit {
        timer?.invalidate()
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
    }
}

private final class CheckpointAnnotation: NSObject, MKAnnotation {
    let point: Checkpoint
    var coordinate: CLLocationCoordinate2D { point.coordinate }
    var title: String? { point.name }
    init(_ point: Checkpoint) { self.point = point }
}
