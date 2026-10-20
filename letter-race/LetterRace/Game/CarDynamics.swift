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

    static func run(path: [LetterPoint]) -> CarSimulation {
        let total = RoadGeometry.length(of: path)
        let cruise = cruiseSpeed
        let maxTime = burnout + total / 12 + 3
        guard path.count >= 2, total > 1, let initial = RoadGeometry.heading(of: path, at: 0) else {
            let only = path.first ?? LetterPoint(x: 50, y: 50)
            let still = Sample(
                time: 0, position: only, body: 0, speed: 0, slip: 0, spin: 0, spinRate: 0,
                burning: false, braking: false, progress: 1
            )
            return CarSimulation(duration: 0, cruise: cruise, samples: [still], skids: [], puffs: [])
        }

        let dt = 1.0 / 60.0
        let driveAccel = 180.0
        let brakeAccel = 200.0
        var position = path[0]
        var body = atan2(initial.y, initial.x)
        var speed = 0.0
        var lateral = 0.0
        var velocityX = 0.0
        var velocityY = 0.0
        var yawRate = 0.0
        var spin = 0.0
        var settledFor = 0.0
        var sincePuff = 1.0
        var anchor = 0.0
        var committed = false
        var straightFor = 0.0
        var samples: [Sample] = []
        var skids: [Skid] = []
        var puffs: [Puff] = []
        var time = 0.0
        let finish = path[path.count - 1]

        while time <= maxTime + 0.0001 {
            let burning = time < burnout
            let onRoad = RoadGeometry.project(position, onto: path, near: anchor)
            anchor = onRoad.progress
            let off = onRoad.distance
            let here = RoadGeometry.heading(of: path, at: anchor) ?? initial
            let soon = RoadGeometry.heading(of: path, at: min(1, anchor + 10 / total)) ?? here
            // Look as far as the current stopping distance, so a fast car brakes
            // for a bend it cannot yet reach slowly.
            let brakeLook = clamp(speed * speed / (2 * brakeAccel) + 10, 14, 40)
            let later = RoadGeometry.heading(of: path, at: min(1, anchor + brakeLook / total)) ?? here
            let roadTurn = wrap(angle(soon) - angle(here))
            let earlyTurn = wrap(angle(later) - angle(here))
            let severity = max(abs(roadTurn), abs(earlyTurn) * 0.85)

            let cornerLimit = cruise / (1 + severity * 1.9)
            // Radians per letter unit. The car only goes as fast as the tires can
            // hold that bend, with a little grip left over so it does not float off.
            let curve = max(abs(roadTurn) / 10, abs(earlyTurn) / max(brakeLook, 1))
            let curveLimit = curve > 0.008 ? (110 / curve).squareRoot() : cruise
            let remaining = max(0, (1 - anchor) * total)
            let gap = position.distance(to: finish)
            let stopping = speed * speed / (2 * brakeAccel) + 3
            var wantedSpeed = burning ? 5.5 : min(cornerLimit, curveLimit)
            if !burning, remaining < stopping {
                wantedSpeed *= max(0, remaining / stopping)
            }
            // Only the last part of the stroke uses the straight-line gap. A loop
            // starts near its own finish, and that must not count as arriving.
            if !burning, anchor > 0.72, gap < 12 {
                wantedSpeed = min(wantedSpeed, max(0, gap * 1.35))
            }
            if !burning, gap > 2.5, gap < 16, speed < 8, anchor > 0.8, off < 4 {
                wantedSpeed = max(wantedSpeed, min(10, gap * 1.1))
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
            let look = RoadGeometry.point(at: min(1, anchor + lookAhead / total), along: path)
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
            } else if !burning, anchor > 0.86, gap < 14, off < 3.5 {
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

            let recovering = off > 4.5 && closingSpeed < 8
            let yawLimit = burning ? 0.4 : (recovering ? 4.5 : 3.15)
            let response = severity < 0.08 ? 3.6 : 6.2
            let targetYaw = clamp(error * response, -yawLimit, yawLimit)
            yawRate += clamp(targetYaw - yawRate, -20 * dt, 20 * dt)
            body = wrap(body + yawRate * dt)

            let forwardX = cos(body)
            let forwardY = sin(body)
            let sideX = -sin(body)
            let sideY = cos(body)
            let along = velocityX * forwardX + velocityY * forwardY
            let side = velocityX * sideX + velocityY * sideY
            let tooWide = off > 4.5 && closingSpeed < 12
            // A steady oval is a turn the tires can hold. The rear steps out only
            // when the road ahead changes direction faster than that.
            let turning = abs(roadTurn) > 0.55 || abs(earlyTurn) > 0.95
            if severity < 0.12 {
                straightFor += dt
            } else {
                straightFor = 0
            }
            // Keep the rear loose for a moment after the bend so the slide can
            // finish, then let the tires hook up once the road is straight.
            if burning || speed < 12 || abs(slipAngle) > 1.15 || straightFor > 0.12 {
                committed = false
            } else if !tooWide && turning && off < 3.2 {
                committed = true
            } else if abs(slipAngle) < 0.1 && abs(roadTurn) < 0.1 {
                committed = false
            }
            let loose = committed && !tooWide
            let tracking = !loose && !tooWide && severity < 0.16
            let latLimit = tooWide ? 280.0 : (loose ? 42.0 : (tracking ? 220.0 : 190.0))
            let latResponse = tooWide ? 16.0 : (loose ? 1.7 : (tracking ? 14.0 : 11.0))
            let delta = wantedSpeed - along
            let longForce: Double
            if burning {
                longForce = clamp(delta, -22, 22)
            } else if abs(delta) < 6 {
                longForce = delta * 6
            } else {
                longForce = sign(delta) * (delta < 0 ? brakeAccel : driveAccel)
            }
            var sideForce = clamp(-side * latResponse, -latLimit, latLimit)
            let circle = tooWide ? 280.0 : (loose ? 70.0 : 230.0)
            let force = hypot(longForce, sideForce)
            if force > circle {
                sideForce *= circle / force
            }
            velocityX += (forwardX * longForce + sideX * sideForce) * dt
            velocityY += (forwardY * longForce + sideY * sideForce) * dt
            position.x += velocityX * dt
            position.y += velocityY * dt
            speed = hypot(velocityX, velocityY)
            lateral = velocityX * sideX + velocityY * sideY

            let placed = RoadGeometry.project(position, onto: path, near: anchor)
            anchor = placed.progress

            let moving = speed > 1
            let velocityAngle = atan2(velocityY, velocityX)
            let slip = moving ? min(1, abs(wrap(body - velocityAngle)) / 0.9) : 0
            let spinRate = burning ? 24.0 : max(3.5, speed * 0.55)
            spin += spinRate * dt

            let rear = LetterPoint(
                x: position.x - forwardX * 5.4,
                y: position.y - forwardY * 5.4
            )
            let layingRubber = burning || loose || abs(slipAngle) > 0.22
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

            samples.append(Sample(
                time: time,
                position: position,
                body: body,
                speed: speed,
                slip: slip,
                spin: spin,
                spinRate: spinRate,
                burning: burning,
                braking: braking,
                progress: anchor
            ))

            let slow = speed < 5 && abs(lateral) < 3
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
