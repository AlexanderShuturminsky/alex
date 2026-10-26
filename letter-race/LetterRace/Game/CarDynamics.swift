import Foundation

/// A car with its own speed. Nothing pulls it onto the ink.
/// The driver brakes for a bend, steers toward the road ahead, and if the tires
/// cannot make the corner the rear steps out until the driver catches it.
struct CarSimulation: Equatable {
    /// Time the rear tires smoke before the car takes off.
    static let burnout = 0.34
    /// How long the car must sit on the finish before the ride is over.
    static let settle = 0.22
    /// Letter units per second on a straight. Corners still force a slower speed.
    static let cruiseSpeed = 120.0

    var duration: Double
    var cruise: Double
    var samples: [Sample]
    var skids: [Skid]
    var puffs: [Puff]

    struct Sample: Equatable {
        var time: Double
        var position: LetterPoint
        var body: Double
        var speed: Double
        var slip: Double
        var spin: Double
        var spinRate: Double
        var burning: Bool
        var braking: Bool
        var progress: Double
    }

    struct Skid: Equatable {
        var time: Double
        var position: LetterPoint
        var body: Double
        var strength: Double
    }

    struct Puff: Equatable {
        var time: Double
        var position: LetterPoint
        var blowX: Double
        var blowY: Double
    }

    /// Live state of the car while chasing the user's finger during `.tracing`.
    struct LiveFollower: Equatable {
        var position: LetterPoint = LetterPoint(x: 0, y: 0)
        var body: Double = 0
        var speed: Double = 0
        var velocityX: Double = 0
        var velocityY: Double = 0
        var yawRate: Double = 0
        var spin: Double = 0
        var slip: Double = 0
        var driftFactor: Double = 0
        var distanceAlong: Double = 0
        var progress: Double = 0
        var elapsed: Double = 0
        var sincePuff: Double = 1.0
        var hasLaunched: Bool = false
        var burning: Bool = false
        var braking: Bool = false
        var skids: [Skid] = []
        var puffs: [Puff] = []

        init(start: LetterPoint = LetterPoint(x: 0, y: 0), heading: LetterPoint = LetterPoint(x: 1, y: 0)) {
            self.position = start
            self.body = atan2(heading.y, heading.x)
        }

        mutating func advance(
            along path: [LetterPoint],
            cumulative: [Double]? = nil,
            dt rawDt: Double,
            holdBack: Double = 5.5
        ) {
            let cum = cumulative ?? RoadGeometry.cumulativeLengths(path)
            let total = cum.last ?? 0
            guard path.count >= 2, total > 1 else { return }
            hasLaunched = true
            let clampedTotal = max(0.0, min(rawDt, 0.08))
            guard clampedTotal > 0.0001 else { return }

            let stepDt = 1.0 / 60.0
            var remainingDt = clampedTotal
            while remainingDt > 0.0001 {
                let dt = min(stepDt, remainingDt)
                remainingDt -= dt
                stepOnce(along: path, cumulative: cum, total: total, dt: dt, holdBack: holdBack)
            }
        }

        private mutating func stepOnce(
            along path: [LetterPoint],
            cumulative: [Double],
            total: Double,
            dt: Double,
            holdBack: Double
        ) {
            let liveBurnout = 0.14
            burning = elapsed < liveBurnout
            let targetDistance = max(0, total - holdBack)
            let remainingToTarget = max(0, targetDistance - distanceAlong)

            let prevProgress = min(1, max(0, distanceAlong / total))
            let here = RoadGeometry.heading(atDistance: distanceAlong, along: path, cumulative: cumulative) ?? LetterPoint(x: 1, y: 0)
            let soon = RoadGeometry.heading(atDistance: min(total, distanceAlong + 9.0), along: path, cumulative: cumulative) ?? here
            let localTurn = CarSimulation.wrap(atan2(soon.y, soon.x) - atan2(here.y, here.x))
            let cusp = RoadGeometry.upcomingCusp(along: path, cumulative: cumulative, from: prevProgress, within: 18.0)

            var wantedSpeed = burning ? 12.0 : CarSimulation.cruiseSpeed / (1.0 + abs(localTurn) * 1.6)
            if let cusp, cusp.distanceAhead < 16.0 {
                wantedSpeed = min(wantedSpeed, max(18.0, cusp.distanceAhead * 4.2))
            }
            if remainingToTarget < 16.0 {
                let catchupSpeed = (2.0 * 180.0 * 0.55 * remainingToTarget).squareRoot()
                wantedSpeed = min(wantedSpeed, remainingToTarget < 0.6 ? 0.0 : max(8.0, catchupSpeed))
            }

            braking = !burning && wantedSpeed + 2.0 < speed
            let accel = wantedSpeed >= speed ? 190.0 : 220.0
            let delta = wantedSpeed - speed
            if abs(delta) <= accel * dt {
                speed = wantedSpeed
            } else {
                speed += (delta > 0 ? accel : -accel) * dt
            }

            distanceAlong = min(targetDistance, distanceAlong + speed * dt)
            progress = min(1, max(0, distanceAlong / total))

            let basePoint = RoadGeometry.point(atDistance: distanceAlong, along: path, cumulative: cumulative)
            let roadHeading = RoadGeometry.heading(atDistance: distanceAlong, along: path, cumulative: cumulative) ?? here
            let roadAngle = atan2(roadHeading.y, roadHeading.x)

            let nearCusp = (cusp?.distanceAhead ?? 99) < 8.0
            let targetDrift = (burning || nearCusp || speed < 18)
                ? 0.0
                : CarSimulation.clamp((abs(localTurn) - 0.32) / 0.45, 0, 0.65)
            driftFactor += (targetDrift - driftFactor) * min(1, 8.0 * dt)
            let turnSign = localTurn >= 0 ? 1.0 : -1.0
            let desiredBody = CarSimulation.wrap(roadAngle + turnSign * driftFactor * 0.28)
            let bodyDiff = CarSimulation.wrap(desiredBody - body)
            let maxYaw = (nearCusp ? 14.0 : 9.5) * dt
            body = CarSimulation.wrap(body + CarSimulation.clamp(bodyDiff, -maxYaw, maxYaw))

            // Slight outward drift offset on tight curves while staying well inside the lane.
            let sideX = -roadHeading.y
            let sideY = roadHeading.x
            let driftOffset = -turnSign * driftFactor * 2.2
            position = LetterPoint(
                x: basePoint.x + sideX * driftOffset,
                y: basePoint.y + sideY * driftOffset
            )
            velocityX = cos(roadAngle) * speed
            velocityY = sin(roadAngle) * speed
            slip = driftFactor
            spin += (burning ? 24.0 : max(3.5, speed * 0.55)) * dt

            let forwardX = cos(body)
            let forwardY = sin(body)
            let rear = LetterPoint(
                x: position.x - forwardX * 5.4,
                y: position.y - forwardY * 5.4
            )
            let layingRubber = burning || driftFactor > 0.25
            if layingRubber {
                skids.append(Skid(
                    time: elapsed,
                    position: rear,
                    body: body,
                    strength: burning ? 0.85 : min(1, 0.35 + driftFactor)
                ))
            }
            sincePuff += dt
            if layingRubber, sincePuff >= 0.05 {
                sincePuff = 0
                puffs.append(Puff(
                    time: elapsed,
                    position: rear,
                    blowX: -forwardX * 6,
                    blowY: -forwardY * 6
                ))
            }
            elapsed += dt
        }
    }

    func sample(at time: Double) -> Sample {
        guard let first = samples.first else {
            return Sample(
                time: 0, position: LetterPoint(x: 0, y: 0), body: 0, speed: 0, slip: 0,
                spin: 0, spinRate: 0, burning: false, braking: false, progress: 0
            )
        }
        if time <= first.time || samples.count == 1 { return first }
        guard let last = samples.last else { return first }
        if time >= last.time { return last }
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if samples[mid].time <= time {
                low = mid
            } else {
                high = mid
            }
        }
        let start = samples[low]
        let end = samples[high]
        let span = max(0.0001, end.time - start.time)
        let t = (time - start.time) / span
        return Sample(
            time: time,
            position: LetterPoint(
                x: start.position.x + (end.position.x - start.position.x) * t,
                y: start.position.y + (end.position.y - start.position.y) * t
            ),
            body: start.body + Self.wrap(end.body - start.body) * t,
            speed: start.speed + (end.speed - start.speed) * t,
            slip: start.slip + (end.slip - start.slip) * t,
            spin: start.spin + (end.spin - start.spin) * t,
            spinRate: start.spinRate + (end.spinRate - start.spinRate) * t,
            burning: start.burning,
            braking: end.braking,
            progress: start.progress + (end.progress - start.progress) * t
        )
    }

    static func run(path: [LetterPoint], startingFrom live: LiveFollower? = nil) -> CarSimulation {
        let total = RoadGeometry.length(of: path)
        let cruise = cruiseSpeed
        guard path.count >= 2, total > 1, let initial = RoadGeometry.heading(of: path, at: 0) else {
            let only = path.first ?? LetterPoint(x: 50, y: 50)
            let still = Sample(
                time: 0, position: only, body: 0, speed: 0, slip: 0, spin: 0, spinRate: 0,
                burning: false, braking: false, progress: 1
            )
            return CarSimulation(duration: 0, cruise: cruise, samples: [still], skids: [], puffs: [])
        }

        let dt = 1.0 / 60.0
        let resumeLive = live?.hasLaunched == true && (live?.distanceAlong ?? 0) > 1.5
        let effectiveBurnout = resumeLive ? 0.0 : burnout
        var anchor = resumeLive ? min(0.96, max(0, (live?.distanceAlong ?? 0) / total)) : 0.0
        if resumeLive, let livePos = live?.position {
            let proj = RoadGeometry.projectForward(livePos, onto: path, from: anchor * 0.85, maxAdvance: 20.0)
            anchor = proj.progress
        }
        var position = resumeLive ? (live?.position ?? path[0]) : path[0]
        let startHeading = RoadGeometry.heading(of: path, at: anchor) ?? initial
        var body = resumeLive ? (live?.body ?? atan2(startHeading.y, startHeading.x)) : atan2(initial.y, initial.x)
        var speed = resumeLive ? max(live?.speed ?? 0, 28.0) : 0.0
        var velocityX = resumeLive ? cos(body) * speed : 0.0
        var velocityY = resumeLive ? sin(body) * speed : 0.0
        var yawRate = resumeLive ? (live?.yawRate ?? 0.0) : 0.0
        var spin = resumeLive ? (live?.spin ?? 0.0) : 0.0
        var settledFor = 0.0
        var sincePuff = resumeLive ? (live?.sincePuff ?? 1.0) : 1.0
        var driftFactor = resumeLive ? (live?.driftFactor ?? 0.0) : 0.0
        var samples: [Sample] = []
        var skids: [Skid] = resumeLive ? (live?.skids.map { Skid(time: 0, position: $0.position, body: $0.body, strength: $0.strength) } ?? []) : []
        var puffs: [Puff] = []
        var time = 0.0
        let finish = path[path.count - 1]
        let remainingLength = max(1.0, (1.0 - anchor) * total)
        let maxTime = effectiveBurnout + remainingLength / 12 + 3.0

        while time <= maxTime + 0.0001 {
            let burning = time < effectiveBurnout
            let stepResult = stepPhysics(
                path: path,
                total: total,
                initial: initial,
                dt: dt,
                time: time,
                burning: burning,
                remainingDistanceOverride: nil,
                position: &position,
                body: &body,
                speed: &speed,
                velocityX: &velocityX,
                velocityY: &velocityY,
                yawRate: &yawRate,
                spin: &spin,
                driftFactor: &driftFactor,
                anchor: &anchor,
                sincePuff: &sincePuff,
                skids: &skids,
                puffs: &puffs
            )

            samples.append(Sample(
                time: time,
                position: position,
                body: body,
                speed: speed,
                slip: stepResult.slip,
                spin: spin,
                spinRate: stepResult.spinRate,
                burning: burning,
                braking: stepResult.braking,
                progress: anchor
            ))

            let slow = speed < 5 && abs(stepResult.lateral) < 3
            if anchor > 0.95, position.distance(to: finish) < 5, slow {
                settledFor += dt
                if settledFor >= settle { break }
            } else {
                settledFor = 0
            }
            time += dt
        }

        let duration = samples.last?.time ?? 0
        return CarSimulation(duration: duration, cruise: cruise, samples: samples, skids: skids, puffs: puffs)
    }

    private struct StepResult {
        var slip: Double
        var spinRate: Double
        var braking: Bool
        var lateral: Double
    }

    private static func stepPhysics(
        path: [LetterPoint],
        total: Double,
        initial: LetterPoint,
        dt: Double,
        time: Double,
        burning: Bool,
        remainingDistanceOverride: Double?,
        position: inout LetterPoint,
        body: inout Double,
        speed: inout Double,
        velocityX: inout Double,
        velocityY: inout Double,
        yawRate: inout Double,
        spin: inout Double,
        driftFactor: inout Double,
        anchor: inout Double,
        sincePuff: inout Double,
        skids: inout [Skid],
        puffs: inout [Puff]
    ) -> StepResult {
        let cruise = cruiseSpeed
        let driveAccel = 180.0
        let brakeAccel = 200.0
        let finish = path[path.count - 1]

        let onRoad = RoadGeometry.projectForward(
            position,
            onto: path,
            from: anchor,
            maxAdvance: max(8.0, speed * dt * 3.5 + 5.0)
        )
        anchor = max(anchor, onRoad.progress)
        var off = onRoad.distance

        let cusp = RoadGeometry.upcomingCusp(along: path, from: anchor, within: 24.0)
        if let cusp, !burning, cusp.distanceAhead <= 2.4 || (cusp.distanceAhead <= 5.0 && position.distance(to: cusp.point) <= 3.2) {
            // Reached a sharp retrace/cusp (such as the waist of B): step onto the outgoing
            // branch and pivot cleanly without looping or doing a 360° donut.
            anchor = min(1, max(anchor, cusp.progress + 1.6 / total))
            let outAngle = angle(cusp.outgoingHeading)
            let turnDiff = wrap(outAngle - body)
            body = wrap(body + clamp(turnDiff, -14.0 * dt, 14.0 * dt))
            speed = min(speed, 16.0)
            velocityX = cos(body) * speed
            velocityY = sin(body) * speed
            driftFactor = 0
            off = position.distance(to: RoadGeometry.point(at: anchor, along: path))
        }

        let here = RoadGeometry.heading(of: path, at: anchor) ?? initial
        let soonProgress: Double
        if let cusp, cusp.distanceAhead > 2.0 {
            soonProgress = min(cusp.progress, anchor + 10 / total)
        } else {
            soonProgress = min(1, anchor + 10 / total)
        }
        let soon = RoadGeometry.heading(of: path, at: soonProgress) ?? here
        // Look as far as the current stopping distance, so a fast car brakes
        // for a bend it cannot yet reach slowly.
        let brakeLook = clamp(speed * speed / (2 * brakeAccel) + 10, 14, 40)
        let laterProgress: Double
        if let cusp, cusp.distanceAhead > 2.0 {
            laterProgress = min(cusp.progress, anchor + brakeLook / total)
        } else {
            laterProgress = min(1, anchor + brakeLook / total)
        }
        let later = RoadGeometry.heading(of: path, at: laterProgress) ?? here
        let roadTurn = wrap(angle(soon) - angle(here))
        let earlyTurn = wrap(angle(later) - angle(here))
        let severity = max(abs(roadTurn), abs(earlyTurn) * 0.85)

        let cornerLimit = cruise / (1 + severity * 1.9)
        // Radians per letter unit. The car only goes as fast as the tires can
        // hold that bend, with a little grip left over so it does not float off.
        let curve = max(abs(roadTurn) / 10, abs(earlyTurn) / max(brakeLook, 1))
        let curveLimit = curve > 0.008 ? (110 / curve).squareRoot() : cruise
        let remaining = remainingDistanceOverride ?? max(0, (1 - anchor) * total)
        let gap = remainingDistanceOverride ?? position.distance(to: finish)
        var wantedSpeed = burning ? 5.5 : min(cornerLimit, curveLimit)
        if !burning, let cusp, cusp.distanceAhead < 22 {
            let cuspSpeed = max(12.0, (2.0 * brakeAccel * 0.45 * max(0, cusp.distanceAhead)).squareRoot())
            wantedSpeed = min(wantedSpeed, cuspSpeed)
        }
        if !burning, remaining < 22 {
            let arrivalDistance = (remainingDistanceOverride == nil && anchor > 0.82) ? max(remaining, min(gap, 14)) : remaining
            let arrivalSpeed = (2.0 * brakeAccel * 0.55 * max(0, arrivalDistance)).squareRoot()
            wantedSpeed = min(wantedSpeed, max(arrivalDistance > 1.8 ? 10.0 : 0.0, arrivalSpeed))
        }
        if !burning, remainingDistanceOverride == nil, anchor > 0.85, gap < 8 {
            wantedSpeed = min(wantedSpeed, max(0, gap * 1.4))
        }
        // A miss lifts the throttle. Accelerating while already wide is how a
        // car leaves the letter instead of driving back onto it.
        if !burning, off > 3.5 {
            wantedSpeed = min(wantedSpeed, max(14, 46 - (off - 3.5) * 5))
        }
        // On a straight, a nose pointed off the road is not a moment to accelerate.
        let headingError = abs(wrap(angle(here) - body))
        if !burning, severity < 0.16, headingError > 0.3 {
            wantedSpeed = min(wantedSpeed, max(16, 34 - (headingError - 0.3) * 20))
        }
        let braking = !burning && wantedSpeed + 1.5 < speed

        let alongNow = velocityX * cos(body) + velocityY * sin(body)
        let sideNow = -velocityX * sin(body) + velocityY * cos(body)
        let slipAngle = atan2(sideNow, max(alongNow, 4))

        let nearest = RoadGeometry.point(at: anchor, along: path)
        let closingSpeed = off > 0.35
            ? ((nearest.x - position.x) * velocityX + (nearest.y - position.y) * velocityY) / off
            : 0
        let lookDistance = burning
            ? 9.0
            : (severity < 0.16
                ? clamp(16 + speed * 0.02, 16, 24)
                : clamp(5 + speed * 0.055, 6, 13))
        let tightened = off > 2 ? lookDistance / (1 + (off - 2) * 0.28) : lookDistance
        let lookAhead = max(2.8, tightened)
        var lookProgress = min(1, anchor + lookAhead / total)
        if let cusp, cusp.distanceAhead > 1.8 {
            lookProgress = min(lookProgress, cusp.progress)
        }
        let look = RoadGeometry.point(at: lookProgress, along: path)
        var aimX = look.x - position.x
        var aimY = look.y - position.y
        // Point back at the asphalt only while the car is still stepping out.
        // Once it is already coming back, look ahead so it merges instead of crossing.
        if !burning, off > 3.5, closingSpeed < 14 {
            let pull = clamp((off - 3.5) / 6, 0, 0.72)
            aimX = aimX * (1 - pull) + (nearest.x - position.x) * pull
            aimY = aimY * (1 - pull) + (nearest.y - position.y) * pull
        } else if !burning, severity < 0.16, off > 1.6, closingSpeed < 20 {
            let pull = clamp((off - 1.6) / 12, 0, 0.28)
            aimX = aimX * (1 - pull) + (nearest.x - position.x) * pull
            aimY = aimY * (1 - pull) + (nearest.y - position.y) * pull
        } else if !burning, remainingDistanceOverride == nil, anchor > 0.86, gap < 14, off < 3.5 {
            aimX = finish.x - position.x
            aimY = finish.y - position.y
        }
        let desired = atan2(aimY, aimX)
        var error = wrap(desired - body)
        // Countersteer only enough to keep a spin from passing the nose.
        // Matching the velocity exactly points the car off the road.
        if !burning, abs(slipAngle) > 0.78 {
            let save = clamp(-slipAngle * 0.9, -0.55, 0.55)
            error = error * 0.72 + save * 0.28
        }

        let nearCusp = (cusp?.distanceAhead ?? 99) < 12.0
        let turnTrigger = max((abs(roadTurn) - 0.50) / 0.28, (abs(earlyTurn) - 0.88) / 0.35)
        let bendIntensity = nearCusp ? 0.0 : clamp(turnTrigger, 0, 1)
        let speedFactor = clamp((speed - 12) / 22, 0, 1)
        let wideRecovery = clamp((off - 3.6) / 2.0, 0, 1)
        let targetDrift = burning ? 0.0 : bendIntensity * speedFactor * (1 - wideRecovery)
        let blendRate = targetDrift > driftFactor ? 12.0 : 5.5
        driftFactor = clamp(driftFactor + (targetDrift - driftFactor) * min(1, blendRate * dt), 0, 1)

        let recovering = off > 4.5 && closingSpeed < 8
        let yawLimit = burning ? 0.4 : (nearCusp ? 6.5 : (recovering ? 4.5 : 3.15 + 0.95 * driftFactor))
        let response = severity < 0.08 ? 3.6 : (nearCusp ? 8.5 : (6.2 + 1.6 * driftFactor))
        let targetYaw = clamp(error * response, -yawLimit, yawLimit)
        yawRate += clamp(targetYaw - yawRate, -24 * dt, 24 * dt)
        body = wrap(body + yawRate * dt)

        let forwardX = cos(body)
        let forwardY = sin(body)
        let sideX = -sin(body)
        let sideY = cos(body)
        let along = velocityX * forwardX + velocityY * forwardY
        let side = velocityX * sideX + velocityY * sideY

        // Continuous curvature-based drift blending: sharp bends smoothly loosen rear
        // lateral grip, while wide offsets or straightaways smoothly restore full grip.
        let latLimit = 240.0 - (240.0 - 95.0) * driftFactor
        let latResponse = 14.0 - (14.0 - 5.5) * driftFactor
        let delta = wantedSpeed - along
        let longForce: Double
        if burning {
            longForce = clamp(delta, -22, 22)
        } else if abs(delta) < 6 {
            longForce = delta * 6
        } else {
            longForce = sign(delta) * (delta < 0 ? brakeAccel : driveAccel)
        }
        let slipGrip = 1.0 - 0.52 * driftFactor
        var sideForce = clamp(-side * latResponse * slipGrip, -latLimit, latLimit)
        let circle = 240.0 - (240.0 - 95.0) * driftFactor
        let force = hypot(longForce, sideForce)
        if force > circle {
            sideForce *= circle / force
        }
        velocityX += (forwardX * longForce + sideX * sideForce) * dt
        velocityY += (forwardY * longForce + sideY * sideForce) * dt
        position.x += velocityX * dt
        position.y += velocityY * dt
        speed = hypot(velocityX, velocityY)
        let lateral = velocityX * sideX + velocityY * sideY

        let placed = RoadGeometry.projectForward(
            position,
            onto: path,
            from: anchor,
            maxAdvance: max(8.0, speed * dt * 3.5 + 5.0)
        )
        anchor = max(anchor, placed.progress)

        // Prevent wide excursions or orbital loops on multi-bowl paths.
        if !burning, placed.distance > 7.5 {
            let pull = min(0.35, (placed.distance - 7.5) * 0.08)
            position.x += (placed.closest.x - position.x) * pull
            position.y += (placed.closest.y - position.y) * pull
        }

        let moving = speed > 1
        let velocityAngle = atan2(velocityY, velocityX)
        let slip = moving ? min(1, abs(wrap(body - velocityAngle)) / 0.9) : 0
        let spinRate = burning ? 24.0 : max(3.5, speed * 0.55)
        spin += spinRate * dt

        let rear = LetterPoint(
            x: position.x - forwardX * 5.4,
            y: position.y - forwardY * 5.4
        )
        let layingRubber = burning || driftFactor > 0.35 || abs(slipAngle) > 0.22
        if layingRubber {
            skids.append(Skid(
                time: time,
                position: rear,
                body: body,
                strength: burning ? 0.85 : min(1, 0.4 + slip)
            ))
        }
        sincePuff += dt
        if layingRubber, sincePuff >= 0.045 {
            sincePuff = 0
            puffs.append(Puff(
                time: time,
                position: rear,
                blowX: -forwardX * 6 + sideX * lateral * 0.25,
                blowY: -forwardY * 6 + sideY * lateral * 0.25
            ))
        }

        return StepResult(slip: slip, spinRate: spinRate, braking: braking, lateral: lateral)
    }

    private static func sign(_ value: Double) -> Double {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }

    private static func angle(_ heading: LetterPoint) -> Double {
        atan2(heading.y, heading.x)
    }

    private static func wrap(_ angle: Double) -> Double {
        var value = angle
        let turn = Double.pi * 2
        while value > Double.pi { value -= turn }
        while value < -Double.pi { value += turn }
        return value
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
}
