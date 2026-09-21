import CoreLocation
import Foundation

/// A location request that can be waited on more than once, given up on, and
/// cancelled.
///
/// Build 2 kept a single `CheckedContinuation` in a property and assigned to
/// it on every request. Two taps of "Near me" before the first resolved
/// overwrote an unresolved continuation, which is not merely a lost callback —
/// leaking a checked continuation traps at runtime. There was also no timeout,
/// so a fix that never arrived left the caller awaiting forever, and no wait
/// for authorization to resolve, so the very first request on a fresh install
/// asked for a location while the permission dialog was still on screen.
///
/// Each waiter here is held under its own token and resumed exactly once, by
/// whichever comes first: the delegate, the timeout, or cancellation.
@MainActor
final class DeviceLocationProvider: NSObject {

    enum Failure: Error, Equatable {
        case denied
        case restricted
        case timedOut
        case unavailable
    }

    private let manager: CLLocationManager
    private var authorizationWaiters: [UUID: CheckedContinuation<CLAuthorizationStatus, Never>] = [:]
    private var fixWaiters: [UUID: CheckedContinuation<Result<CLLocation, Failure>, Never>] = [:]

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        // "Shops around here" does not need a street-level fix, and asking for
        // less is the least the owner has to give up to get an answer.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Asks for permission and waits for the answer.
    ///
    /// Returns immediately when the question has already been settled, which
    /// is the common case and the one Build 2 got wrong by requesting a
    /// location straight afterwards regardless.
    @discardableResult
    func requestAuthorization(timeout: Duration = .seconds(60)) async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }

        let token = UUID()
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<CLAuthorizationStatus, Never>) in
            authorizationWaiters[token] = continuation
            manager.requestWhenInUseAuthorization()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                // Resumes only if nobody else got there first.
                self?.finishAuthorization(token, with: self?.manager.authorizationStatus ?? .notDetermined)
            }
        }
        return status
    }

    /// A usable fix, or a reason there is none.
    ///
    /// - Parameter maxAge: how stale a cached fix may be before it is ignored.
    ///   A location from this morning is not where the owner is shopping now.
    func fix(
        maxAge: TimeInterval = 300,
        timeout: Duration = .seconds(15)
    ) async -> Result<CLLocation, Failure> {
        switch manager.authorizationStatus {
        case .denied: return .failure(.denied)
        case .restricted: return .failure(.restricted)
        case .notDetermined:
            let status = await requestAuthorization()
            if status == .denied { return .failure(.denied) }
            if status == .restricted { return .failure(.restricted) }
            if status == .notDetermined { return .failure(.timedOut) }
        default: break
        }

        // A recent fix is worth having without spinning the radios up again —
        // but only a recent one, and only one accurate enough to be about
        // where the owner is rather than which county.
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) <= maxAge,
           cached.horizontalAccuracy >= 0,
           cached.horizontalAccuracy <= 5_000 {
            return .success(cached)
        }

        let token = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<CLLocation, Failure>, Never>) in
            fixWaiters[token] = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finishFix(token, with: .failure(.timedOut))
            }
        }
    }

    // MARK: - Resolving exactly once

    private func finishAuthorization(_ token: UUID, with status: CLAuthorizationStatus) {
        guard let waiter = authorizationWaiters.removeValue(forKey: token) else { return }
        waiter.resume(returning: status)
    }

    private func finishAllAuthorization(with status: CLAuthorizationStatus) {
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters.values { waiter.resume(returning: status) }
    }

    private func finishFix(_ token: UUID, with result: Result<CLLocation, Failure>) {
        guard let waiter = fixWaiters.removeValue(forKey: token) else { return }
        waiter.resume(returning: result)
    }

    private func finishAllFixes(with result: Result<CLLocation, Failure>) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        for waiter in waiters.values { waiter.resume(returning: result) }
    }
}

extension DeviceLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let last {
                self.finishAllFixes(with: .success(last))
            } else {
                self.finishAllFixes(with: .failure(.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A CoreLocation failure is not a denial. Reporting it as one
            // sends the owner to Settings to fix something that is not broken.
            let failure: Failure = (error as? CLError)?.code == .denied ? .denied : .unavailable
            self.finishAllFixes(with: .failure(failure))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard status != .notDetermined else { return }
            self.finishAllAuthorization(with: status)
            if status == .denied {
                self.finishAllFixes(with: .failure(.denied))
            } else if status == .restricted {
                self.finishAllFixes(with: .failure(.restricted))
            }
        }
    }
}
