import SwiftUI
import OdomindCore

/// The silhouettes themselves, authored in the 250 × 100 canonical box with
/// the front of the vehicle at the left.
///
/// Read these as drawings, not as data: the numbers are where the lines go.
/// Every one shares the ground line, the wheel size and the stroke weight, so
/// a garage holding a pickup and a coupe looks like one set of illustrations.
extension VehicleDrawing {
    static func specification(for shape: VehicleShape) -> SilhouetteSpec {
        switch shape {
        case .illustration(let illustration):
            switch illustration {
            case .jeepWranglerJKUnlimited: return jeepWranglerJKUnlimited
            case .jeepWranglerJKTwoDoor: return jeepWranglerJKTwoDoor
            }
        case .bodyStyle(let style):
            switch style {
            case .sedan: return sedan
            case .hatchback: return hatchback
            case .coupe: return coupe
            case .wagon: return wagon
            case .crossover: return crossover
            case .suv: return suv
            case .offRoadSUV: return offRoadSUV
            case .pickup: return pickup
            case .van: return van
            }
        }
    }

    // MARK: - Matched illustrations

    /// 2007–2018 Wrangler Unlimited (JK), four doors, hard top.
    ///
    /// The cues that make it this vehicle and not an SUV-shaped box: an almost
    /// upright windshield, a flat hard top, a flat vertical grille with a round
    /// headlight, squared-off arches with flares, and the spare on the
    /// tailgate. Three pillars means four panes means four doors — which is the
    /// whole difference between this drawing and the one below it.
    static let jeepWranglerJKUnlimited = SilhouetteSpec(
        body: [
            ArtPoint(24, 70, 2),
            ArtPoint(20, 43, 2),
            ArtPoint(66, 41, 2),
            ArtPoint(83, 16, 3),
            ArtPoint(219, 16, 3),
            ArtPoint(223, 66, 3),
            ArtPoint(223, 70, 2)
        ],
        greenhouse: [
            ArtPoint(69, 39, 1.5),
            ArtPoint(86, 20, 2),
            ArtPoint(206, 20, 2),
            ArtPoint(206, 39, 1.5)
        ],
        pillars: [94, 134, 174],
        frontWheelX: 54,
        rearWheelX: 198,
        wheelRadius: 19,
        bodyBottomY: 70,
        beltlineY: 41,
        squareArches: true,
        roundHeadlight: true,
        headlight: CGPoint(x: 28, y: 52),
        spare: CGPoint(x: 233, y: 47)
    )

    /// 2007–2018 Wrangler (JK), two doors. Same front, shorter body, two
    /// pillars — one long door window and a quarter light.
    static let jeepWranglerJKTwoDoor = SilhouetteSpec(
        body: [
            ArtPoint(24, 70, 2),
            ArtPoint(20, 43, 2),
            ArtPoint(66, 41, 2),
            ArtPoint(83, 16, 3),
            ArtPoint(196, 16, 3),
            ArtPoint(200, 66, 3),
            ArtPoint(200, 70, 2)
        ],
        greenhouse: [
            ArtPoint(69, 39, 1.5),
            ArtPoint(86, 20, 2),
            ArtPoint(183, 20, 2),
            ArtPoint(183, 39, 1.5)
        ],
        pillars: [94, 152],
        frontWheelX: 54,
        rearWheelX: 176,
        wheelRadius: 19,
        bodyBottomY: 70,
        beltlineY: 41,
        squareArches: true,
        roundHeadlight: true,
        headlight: CGPoint(x: 28, y: 52),
        spare: CGPoint(x: 210, y: 47)
    )

    // MARK: - Body styles

    static let sedan = SilhouetteSpec(
        body: [
            ArtPoint(16, 76, 6),
            ArtPoint(12, 57, 8),
            ArtPoint(56, 51, 10),
            ArtPoint(95, 22, 12),
            ArtPoint(168, 22, 12),
            ArtPoint(206, 53, 10),
            ArtPoint(236, 57, 8),
            ArtPoint(234, 76, 6)
        ],
        greenhouse: [
            ArtPoint(60, 49, 4),
            ArtPoint(99, 26, 6),
            ArtPoint(165, 26, 6),
            ArtPoint(194, 49, 4)
        ],
        pillars: [106, 150, 182],
        frontWheelX: 56,
        rearWheelX: 192,
        wheelRadius: 17,
        bodyBottomY: 76,
        beltlineY: 50,
        headlight: CGPoint(x: 20, y: 60)
    )

    static let hatchback = SilhouetteSpec(
        body: [
            ArtPoint(14, 76, 6),
            ArtPoint(11, 56, 8),
            ArtPoint(52, 50, 10),
            ArtPoint(88, 22, 12),
            ArtPoint(178, 22, 10),
            ArtPoint(208, 56, 6),
            ArtPoint(210, 72, 8),
            ArtPoint(206, 76, 4)
        ],
        greenhouse: [
            ArtPoint(56, 48, 4),
            ArtPoint(92, 26, 6),
            ArtPoint(176, 26, 6),
            ArtPoint(196, 48, 4)
        ],
        pillars: [100, 141, 172],
        frontWheelX: 54,
        rearWheelX: 184,
        wheelRadius: 17,
        bodyBottomY: 76,
        beltlineY: 49,
        headlight: CGPoint(x: 19, y: 59)
    )

    static let coupe = SilhouetteSpec(
        body: [
            ArtPoint(16, 77, 6),
            ArtPoint(12, 58, 8),
            ArtPoint(54, 51, 12),
            ArtPoint(100, 24, 14),
            ArtPoint(150, 24, 16),
            ArtPoint(214, 55, 14),
            ArtPoint(234, 59, 8),
            ArtPoint(232, 77, 6)
        ],
        greenhouse: [
            ArtPoint(58, 50, 4),
            ArtPoint(104, 28, 8),
            ArtPoint(150, 28, 10),
            ArtPoint(198, 50, 6)
        ],
        pillars: [112, 172],
        frontWheelX: 58,
        rearWheelX: 190,
        wheelRadius: 17,
        bodyBottomY: 77,
        beltlineY: 51,
        headlight: CGPoint(x: 20, y: 61)
    )

    static let wagon = SilhouetteSpec(
        body: [
            ArtPoint(14, 76, 6),
            ArtPoint(11, 56, 8),
            ArtPoint(56, 50, 10),
            ArtPoint(92, 22, 12),
            ArtPoint(216, 22, 8),
            ArtPoint(230, 52, 6),
            ArtPoint(231, 72, 8),
            ArtPoint(227, 76, 4)
        ],
        greenhouse: [
            ArtPoint(60, 48, 4),
            ArtPoint(96, 26, 6),
            ArtPoint(214, 26, 4),
            ArtPoint(218, 48, 4)
        ],
        pillars: [104, 146, 188],
        frontWheelX: 56,
        rearWheelX: 194,
        wheelRadius: 17,
        bodyBottomY: 76,
        beltlineY: 49,
        headlight: CGPoint(x: 19, y: 59)
    )

    static let crossover = SilhouetteSpec(
        body: [
            ArtPoint(14, 74, 6),
            ArtPoint(12, 51, 8),
            ArtPoint(58, 45, 10),
            ArtPoint(90, 20, 12),
            ArtPoint(190, 20, 12),
            ArtPoint(217, 53, 10),
            ArtPoint(219, 70, 8),
            ArtPoint(215, 74, 4)
        ],
        greenhouse: [
            ArtPoint(62, 43, 4),
            ArtPoint(94, 24, 6),
            ArtPoint(188, 24, 6),
            ArtPoint(205, 43, 4)
        ],
        pillars: [104, 148, 186],
        frontWheelX: 55,
        rearWheelX: 193,
        wheelRadius: 18,
        bodyBottomY: 74,
        beltlineY: 44,
        headlight: CGPoint(x: 20, y: 55)
    )

    static let suv = SilhouetteSpec(
        body: [
            ArtPoint(14, 72, 5),
            ArtPoint(11, 47, 7),
            ArtPoint(56, 43, 8),
            ArtPoint(82, 18, 10),
            ArtPoint(204, 18, 10),
            ArtPoint(219, 48, 8),
            ArtPoint(221, 68, 7),
            ArtPoint(217, 72, 4)
        ],
        greenhouse: [
            ArtPoint(60, 41, 3),
            ArtPoint(86, 22, 5),
            ArtPoint(202, 22, 5),
            ArtPoint(208, 41, 3)
        ],
        pillars: [100, 142, 184],
        frontWheelX: 56,
        rearWheelX: 194,
        wheelRadius: 18,
        bodyBottomY: 72,
        beltlineY: 42,
        headlight: CGPoint(x: 19, y: 53)
    )

    /// The generic off-roader, for a vehicle Odomind has no exact drawing of.
    ///
    /// Deliberately *not* a second Wrangler. It keeps the cues that make a
    /// vehicle read as off-road — height, square arches, a near-flat roof —
    /// but has a raked screen, a conventional lamp and no tailgate spare, so
    /// nobody mistakes the fallback for a matched drawing of their own car.
    static let offRoadSUV = SilhouetteSpec(
        body: [
            ArtPoint(13, 71, 5),
            ArtPoint(11, 46, 7),
            ArtPoint(58, 42, 6),
            ArtPoint(84, 18, 8),
            ArtPoint(210, 18, 8),
            ArtPoint(220, 50, 7),
            ArtPoint(221, 67, 6),
            ArtPoint(217, 71, 4)
        ],
        greenhouse: [
            ArtPoint(62, 40, 3),
            ArtPoint(88, 22, 5),
            ArtPoint(207, 22, 4),
            ArtPoint(209, 40, 3)
        ],
        pillars: [100, 142, 182],
        frontWheelX: 56,
        rearWheelX: 195,
        wheelRadius: 19,
        bodyBottomY: 71,
        beltlineY: 41,
        squareArches: true,
        headlight: CGPoint(x: 20, y: 53)
    )

    /// Crew cab, short bed — the shape most pickups on a driveway now are.
    static let pickup = SilhouetteSpec(
        body: [
            ArtPoint(12, 72, 4),
            ArtPoint(9, 45, 5),
            ArtPoint(58, 41, 4),
            ArtPoint(80, 17, 6),
            ArtPoint(152, 17, 6),
            ArtPoint(158, 44, 3),
            ArtPoint(236, 44, 3),
            ArtPoint(238, 70, 4),
            ArtPoint(234, 72, 3)
        ],
        greenhouse: [
            ArtPoint(64, 39, 2),
            ArtPoint(84, 21, 4),
            ArtPoint(150, 21, 4),
            ArtPoint(150, 39, 2)
        ],
        pillars: [98, 124],
        frontWheelX: 54,
        rearWheelX: 196,
        wheelRadius: 19,
        bodyBottomY: 72,
        beltlineY: 40,
        squareArches: true,
        headlight: CGPoint(x: 19, y: 52)
    )

    static let van = SilhouetteSpec(
        body: [
            ArtPoint(14, 75, 6),
            ArtPoint(10, 49, 7),
            ArtPoint(36, 39, 9),
            ArtPoint(64, 16, 13),
            ArtPoint(214, 14, 9),
            ArtPoint(229, 40, 7),
            ArtPoint(231, 71, 8),
            ArtPoint(227, 75, 4)
        ],
        greenhouse: [
            ArtPoint(44, 42, 3),
            ArtPoint(68, 20, 8),
            ArtPoint(212, 19, 5),
            ArtPoint(218, 42, 3)
        ],
        pillars: [88, 132, 180],
        frontWheelX: 52,
        rearWheelX: 196,
        wheelRadius: 17,
        bodyBottomY: 75,
        beltlineY: 43,
        headlight: CGPoint(x: 18, y: 56)
    )
}
