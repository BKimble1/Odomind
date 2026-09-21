import Foundation
import Observation
import OdomindCore

/// A message shown to the owner when something went wrong.
///
/// Every failure Odomind can hit — a save that did not land, a provider that
/// did not answer, a backup that would not apply — becomes one of these rather
/// than a silent no-op.
struct AppAlert: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var message: String
    /// What the owner can do about it, when there is something.
    var recoverySuggestion: String?

    init(title: String, message: String, recoverySuggestion: String? = nil) {
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }

    static func saveFailed(_ error: Error) -> AppAlert {
        AppAlert(
            title: "Could not save",
            message: (error as? LocalizedError)?.errorDescription ?? String(describing: error),
            recoverySuggestion: "Your entry is still here. Try again, or take a note of it before closing."
        )
    }
}

/// The app's single source of truth.
///
/// Screens read a snapshot and pre-computed schedule evaluations; they never
/// touch the store or the engine themselves. Every mutation goes through a
/// method here, which writes, reloads, re-evaluates and re-syncs reminders in
/// that order — so the due dates on screen and the reminders on the system can
/// never disagree.
@MainActor
@Observable
final class AppModel {
    let store: OdomindStore
    let catalogService: CatalogService
    let attachments: AttachmentStore
    let reminderCoordinator: ReminderCoordinator
    let identificationProvider: VehicleIdentificationProvider
    let backupService: BackupService
    let exportService: ExportService
    let clock: OdomindClock
    /// StoreKit's answer about Pro. Observed, so a renewal or a refund that
    /// arrives while a screen is open redraws it.
    let entitlements: EntitlementService
    /// Real photographs, resolved in the background and cached.
    let photos: VehiclePhotoService
    /// Where the owner is shopping. One decision, shared by Home and Parts,
    /// kept across launches.
    let shoppingLocation: ShoppingLocationService
    /// The configurations a vehicle was actually sold in, for the setup step.
    let vehicleOptions: VehicleOptionsService

    private(set) var snapshot = GarageSnapshot()
    private(set) var evaluationsByVehicle: [UUID: [ScheduleEvaluation]] = [:]
    private(set) var estimateByVehicle: [UUID: MileageEstimateResult] = [:]
    private(set) var reminderReport: ReminderSyncReport = .never
    private(set) var isLoaded = false

    var alert: AppAlert?
    /// Set when a notification or link should take the owner somewhere.
    var pendingDeepLink: DeepLink?

    /// The calendar used for every date calculation. Read from the system so a
    /// time-zone change while the app is open is picked up on the next refresh.
    var calendar: Calendar { Calendar.current }

    init(
        store: OdomindStore,
        catalogService: CatalogService = CatalogService(),
        attachments: AttachmentStore,
        notificationScheduler: NotificationScheduling = SystemNotificationScheduler(),
        identificationProvider: VehicleIdentificationProvider = VPICClient(),
        clock: OdomindClock = SystemClock()
    ) {
        self.store = store
        self.catalogService = catalogService
        self.attachments = attachments
        self.reminderCoordinator = ReminderCoordinator(scheduler: notificationScheduler)
        self.identificationProvider = identificationProvider
        self.backupService = BackupService(attachments: attachments)
        self.exportService = ExportService()
        self.clock = clock
        self.entitlements = EntitlementService()
        // Stubbed in UI tests by default: the pull-request gate must not go
        // red because Commons or fueleconomy.gov is having an afternoon, and a
        // journey test must not wait on a location fix that will never come.
        // The screenshot pass opts back in by name — see `providersAreLive`.
        self.photos = VehiclePhotoService(enabled: Self.providersAreLive)
        self.shoppingLocation = ShoppingLocationService()
        self.vehicleOptions = VehicleOptionsService(enabled: Self.providersAreLive)
    }

    /// Launch argument that makes the app run against a throwaway store.
    ///
    /// UI tests pass it so each run starts from onboarding and never touches —
    /// or is influenced by — whatever is on the simulator already.
    static let uiTestingArgument = "-odomind-ui-testing"

    /// Launch argument that seeds the sample vehicle, used by the screenshot
    /// pass so the captures show a populated app. Only honoured alongside the
    /// UI-testing store, so it can never touch a real garage.
    static let seedSampleArgument = "-odomind-seed-sample"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    static var shouldSeedSample: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains(seedSampleArgument)
    }

    /// Launch argument that lets a UI-test build reach the real providers.
    ///
    /// The default has to stay off. A pull-request gate that fails when
    /// Wikimedia Commons is slow is a gate that gets ignored.
    ///
    /// The screenshot pass is the exception, and the brief says why: "Review
    /// them visually; fixture-only screenshots do not prove a live provider
    /// works." A capture of a recorded answer proves the layout and nothing
    /// about the service, so the capture job opts in by name and takes the
    /// consequence — if a provider is down when it runs, the screenshot shows
    /// Odomind's honest fallback and is reported as such rather than retaken
    /// until it looks better.
    static let liveProvidersArgument = "-odomind-live-providers"

    /// True outside UI tests, and inside one only when it asked for it.
    static var providersAreLive: Bool {
        guard isUITesting else { return true }
        return ProcessInfo.processInfo.arguments.contains(liveProvidersArgument)
    }

    /// Launch argument that keeps the welcome permission step in a UI test.
    ///
    /// Off by default under test. The step puts two system dialogues between
    /// onboarding and the vehicle flow, and every journey test wants the
    /// vehicle flow — so the one test that is *about* permissions opts in,
    /// and the rest are not made to walk through a screen they are not
    /// testing.
    static let exercisePermissionsArgument = "-odomind-exercise-permissions"

    static var shouldOfferPermissionStep: Bool {
        guard isUITesting else { return true }
        return ProcessInfo.processInfo.arguments.contains(exercisePermissionsArgument)
    }

    /// Builds the model an app launch uses.
    static func live() throws -> AppModel {
        let uiTesting = isUITesting
        let store = try OdomindStore(inMemory: uiTesting)
        let attachments: AttachmentStore
        if uiTesting {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OdomindUITests-\(UUID().uuidString)", isDirectory: true)
            attachments = try AttachmentStore(directory: directory)
        } else {
            attachments = try AttachmentStore()
        }
        // `CatalogService.live()` prefers a validated installed update over
        // the bundled catalog, and silently falls back to bundled if there is
        // not a good one.
        return AppModel(store: store, catalogService: .live(), attachments: attachments)
    }

    // MARK: - Loading

    func load() async {
        refresh()
        if AppModel.shouldSeedSample, snapshot.vehicles.isEmpty {
            addDemoContent()
        }
        isLoaded = true
        // Records the garage size before any limit can apply. Must run before
        // the first screen reads `canAddVehicle`.
        recordGrandfatheredAllowanceIfNeeded()
        sweepOrphanedAttachments()

        // Deliberately not awaited. Asking the App Store about products is a
        // network round trip, and launch must not wait on one — the app is
        // usable with no connection at all. `status` stays `.unknown` until it
        // answers, and `canAddVehicle` is permissive while it is unknown, so
        // nothing is gated on a call that has not come back.
        Task { await entitlements.start() }

        await syncReminders()
    }

    /// Re-reads everything and recomputes the schedule.
    ///
    /// Called after every write. Cheap enough to do wholesale — a garage is a
    /// handful of vehicles — and wholesale is what makes the screens impossible
    /// to leave stale.
    func refresh() {
        do {
            snapshot = try store.snapshot()
        } catch {
            alert = AppAlert(
                title: "Could not read your data",
                message: (error as? LocalizedError)?.errorDescription ?? String(describing: error),
                recoverySuggestion: "Restart Odomind. If this keeps happening, restore from a backup."
            )
            return
        }
        recomputeSchedule()
    }

    func recomputeSchedule() {
        let now = clock.now
        let calendar = self.calendar
        let definitions = catalogService.catalog?.definitionsByID ?? [:]

        var evaluations: [UUID: [ScheduleEvaluation]] = [:]
        var estimates: [UUID: MileageEstimateResult] = [:]

        for vehicle in snapshot.vehicles {
            let context = ScheduleContext.build(
                vehicle: vehicle,
                readings: snapshot.readings(for: vehicle.id),
                serviceRecords: snapshot.serviceRecords(for: vehicle.id),
                declaredTypicalDistancePerMonth: snapshot.declaredTypicalDistances[vehicle.id],
                asOf: now,
                calendar: calendar
            )
            evaluations[vehicle.id] = ScheduleEngine.evaluateAll(
                snapshot.planItems(for: vehicle.id),
                definitions: definitions,
                in: context
            )
            if let estimate = context.estimate {
                estimates[vehicle.id] = .available(estimate)
            } else if let reason = context.estimateUnavailableReason {
                estimates[vehicle.id] = .unavailable(reason)
            }
        }

        evaluationsByVehicle = evaluations
        estimateByVehicle = estimates
    }

    // MARK: - Selection

    var selectedVehicleID: UUID? {
        snapshot.settings.selectedVehicleID ?? snapshot.vehicles.first?.id
    }

    var selectedVehicle: Vehicle? {
        guard let selectedVehicleID else { return nil }
        return snapshot.vehicle(id: selectedVehicleID)
    }

    var hasVehicles: Bool { !snapshot.vehicles.isEmpty }

    var needsOnboarding: Bool { snapshot.vehicles.isEmpty }

    func selectVehicle(_ id: UUID) {
        var settings = snapshot.settings
        settings.selectedVehicleID = id
        persist(settings: settings)
    }

    func persist(settings: AppSettings) {
        do {
            try store.save(settings: settings)
            refresh()
        } catch {
            alert = .saveFailed(error)
        }
    }

    // MARK: - Derived reads

    func evaluations(for vehicleID: UUID) -> [ScheduleEvaluation] {
        evaluationsByVehicle[vehicleID] ?? []
    }

    func evaluation(planItemID: UUID) -> ScheduleEvaluation? {
        for (_, list) in evaluationsByVehicle {
            if let match = list.first(where: { $0.planItemID == planItemID }) { return match }
        }
        return nil
    }

    func planItem(id: UUID) -> MaintenancePlanItem? {
        snapshot.planItems.first { $0.id == id }
    }

    func ledger(for vehicle: Vehicle) -> OdometerLedger {
        OdometerLedger(vehicle: vehicle, readings: snapshot.readings(for: vehicle.id))
    }

    func latestReading(for vehicleID: UUID) -> OdometerReading? {
        snapshot.readings(for: vehicleID).max { $0.recordedOn < $1.recordedOn }
    }

    func estimate(for vehicleID: UUID) -> MileageEstimateResult? {
        estimateByVehicle[vehicleID]
    }

    /// Tasks in each due state, in urgency order.
    func grouped(for vehicleID: UUID) -> [DueGroup] {
        ScheduleEngine.grouped(evaluations(for: vehicleID).filter { $0.state != .notApplicable })
    }

    var openProposalCount: Int {
        snapshot.planItems.filter(\.hasPendingProposal).count
    }

    // MARK: - Reminders

    func syncReminders() async {
        let desired = ReminderCoordinator.plan(
            snapshot: snapshot,
            evaluationsByVehicle: evaluationsByVehicle,
            now: clock.now,
            calendar: calendar
        )
        reminderReport = await reminderCoordinator.synchronize(
            desired: desired,
            remindersEnabled: snapshot.settings.reminders.remindersEnabled,
            now: clock.now
        )
    }

    /// Asks for notification permission at the moment the owner turns a
    /// reminder on — never at launch.
    func enableReminders() async -> Bool {
        let status = await reminderCoordinator.scheduler.authorizationStatus()
        var granted = status.allowsScheduling
        if status == .notDetermined {
            granted = await reminderCoordinator.scheduler.requestAuthorization()
        }

        var settings = snapshot.settings
        settings.reminders.remindersEnabled = granted
        persist(settings: settings)
        await syncReminders()

        if !granted {
            alert = AppAlert(
                title: "Notifications are off",
                message: "Odomind cannot send reminders without notification permission.",
                recoverySuggestion: "Turn notifications on for Odomind in Settings, then try again. Everything else in the app keeps working."
            )
        }
        return granted
    }

    func disableReminders() async {
        var settings = snapshot.settings
        settings.reminders.remindersEnabled = false
        persist(settings: settings)
        await syncReminders()
    }

    func updateReminderSettings(_ update: (inout ReminderSettings) -> Void) async {
        var settings = snapshot.settings
        update(&settings.reminders)
        persist(settings: settings)
        await syncReminders()
    }

    // MARK: - Attachments

    /// Deletes attachment files nothing refers to any more.
    func sweepOrphanedAttachments() {
        let known = Set(snapshot.attachments.map(\.fileName))
        attachments.removeOrphans(keepingFileNames: known)
    }

    func attachmentData(_ id: UUID) -> Data? {
        guard let metadata = snapshot.attachment(id: id) else { return nil }
        return try? attachments.data(for: metadata)
    }
}
