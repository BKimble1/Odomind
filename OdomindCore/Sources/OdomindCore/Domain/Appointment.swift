import Foundation

/// A booking the owner made, as distinct from work that happened.
///
/// Odomind keeps these apart on purpose. A service record says a job was done;
/// an appointment says someone intends to do it on a date. Conflating them is
/// how an app ends up resetting a maintenance interval because a booking
/// existed, or claiming a car was serviced because the owner wrote down a date.
///
/// An appointment also does not move a deadline. If the garage can only see the
/// car three weeks after the brake fluid is due, both facts are true and the
/// calendar shows both.
public struct Appointment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var vehicleID: UUID
    /// The day the appointment is on. Stored as the start of that day in the
    /// owner's calendar; appointments are day-grained because that is what an
    /// owner actually knows when they book one.
    public var scheduledOn: Date
    public var title: String
    /// Jobs the owner expects this visit to cover. Empty is allowed: "the shop
    /// is looking at it" is a real appointment.
    public var planItemIDs: [UUID]
    public var location: String?
    public var notes: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        scheduledOn: Date,
        title: String,
        planItemIDs: [UUID] = [],
        location: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.scheduledOn = scheduledOn
        self.title = title
        self.planItemIDs = planItemIDs
        self.location = location
        self.notes = notes
        self.createdAt = createdAt
    }
}
