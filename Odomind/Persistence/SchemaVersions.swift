import Foundation
import SwiftData

/// Version 1 of the persistent schema.
///
/// The model types live at file scope rather than nested inside this enum so
/// the app code reads naturally. When a version 2 is needed, copy the version 1
/// class definitions into a `OdomindSchemaV1` namespace at that point, add
/// `OdomindSchemaV2`, and add a stage to `OdomindMigrationPlan`. The procedure
/// is written out in `docs/ARCHITECTURE.md` so the first person to need it does
/// not have to work it out under pressure.
enum OdomindSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            StoredVehicle.self,
            StoredOdometerReading.self,
            StoredPlanItem.self,
            StoredServiceRecord.self,
            StoredSpecification.self,
            StoredAttachment.self,
            StoredSettings.self
        ]
    }
}

enum OdomindMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OdomindSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum OdomindSchema {
    static var current: Schema { Schema(versionedSchema: OdomindSchemaV1.self) }
}
