import Foundation

/// A car with its own speed. How fast the finger drew the stroke does not set the pace:
/// the car cruises, brakes before a bend, and steps the rear out on a sharp one.
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
        var position = path[0]
        var body = atan2(initial.y, initial.x)
        var speed = 0.0
        var lateral = 0.0
        var spin = 0.0
        var slideHold = 0.0
        var settledFor = 0.0
        var sincePuff = 1.0
        var anchor = 0.0
        var samples: [Sample] = []
        var skids: [Skid] = []
        var puffs: [Puff] = []
        var time = 0.0

        while time <= maxTime + 0.0001 {
            let burning = time < burnout
            let here = RoadGeometry.heading(of: path, at: anchor) ?? initial
            let soon = RoadGeometry.heading(of: path, at: min(1, anchor + 14 / total)) ?? here
            let later = RoadGeometry.heading(of: path, at: min(1, anchor + 28 / total)) ?? here
            let roadTurn = wrap(angle(soon) - angle(here))
            let earlyTurn = wrap(angle(later) - angle(here))
            let severity = max(abs(roadTurn), abs(earlyTurn))

            let cornerLimit = cruise / (1 + severity * 2.1)
            let remaining = max(0, (1 - anchor) * total)
            let stopping = speed * speed / (2 * 240) + 5
            let endScale = remaining < stopping ? max(0, remaining / max(stopping, 0.001)) : 1.0
            let wantedSpeed = burning ? 6.0 : cornerLimit * endScale
            let braking = !burning && wantedSpeed + 2 < speed
            let accel = burning ? 24.0 : (braking ? 280.0 : 180.0)
            speed += clamp(wantedSpeed - speed, -accel * dt, accel * dt)
            if speed < 0 { speed = 0 }

            let lookAhead = min(1, anchor + (7.5 + speed * 0.035) / total)
            let look = RoadGeometry.point(at: lookAhead, along: path)
            let desired = atan2(look.y - position.y, look.x - position.x)
            let steer = clamp(wrap(desired - body), -0.95, 0.95)
            let wheelbase = 8.0
            let demandedYaw = speed / wheelbase * tan(steer)
            let maxYaw = burning ? 0.55 : 2.4
            let yaw = clamp(demandedYaw, -maxYaw, maxYaw)
            body = wrap(body + yaw * dt)

            if !burning && abs(roadTurn) > 0.5 && speed > 6.5 {
                slideHold = 0.42
            } else {
                slideHold = max(0, slideHold - dt)
            }
            let sliding = slideHold > 0 && !burning
            if sliding {
                let outward: Double
                if roadTurn == 0 {
                    outward = lateral >= 0 ? 1 : -1
                } else {
                    outward = roadTurn > 0 ? -1 : 1
                }
                let wanted = outward * min(11, 5 + abs(roadTurn) * 3.2)
                lateral += (wanted - lateral) * min(1, 9 * dt)
            } else if !burning {
                lateral *= max(0, 1 - 6 * dt)
            }
            lateral = clamp(lateral, -12, 12)
            if burning {
                lateral *= max(0, 1 - 4 * dt)
            }

            let forwardX = cos(body)
            let forwardY = sin(body)
            let sideX = -sin(body)
            let sideY = cos(body)
            var velocityX = forwardX * speed + sideX * lateral
            var velocityY = forwardY * speed + sideY * lateral

            let nearest = RoadGeometry.project(position, onto: path, near: anchor)
            let off = nearest.distance
            var pull = burning ? 0.4 : (sliding ? 1.4 : 6.0)
            if off > 9 { pull += (off - 9) * 1.2 }
            if anchor > 0.93 { pull += 6 }
            velocityX += (nearest.closest.x - position.x) * pull * dt
            velocityY += (nearest.closest.y - position.y) * pull * dt

            position.x += velocityX * dt
            position.y += velocityY * dt

            let settled = RoadGeometry.project(position, onto: path, near: anchor)
            if settled.distance > 8.2 {
                let keep = 8.2 / settled.distance
                position.x = settled.closest.x + (position.x - settled.closest.x) * keep
                position.y = settled.closest.y + (position.y - settled.closest.y) * keep
                lateral *= 0.7
            }

            if anchor > 0.92, let finish = path.last {
                let catchUp = min(1, (anchor > 0.97 ? 9 : 2.5) * dt)
                position.x += (finish.x - position.x) * catchUp
                position.y += (finish.y - position.y) * catchUp
            }

            let placed = RoadGeometry.project(position, onto: path, near: anchor)
            anchor = placed.progress

            let velocityAngle = atan2(velocityY, velocityX)
            let moving = hypot(velocityX, velocityY) > 1
            let slip = moving ? min(1, abs(wrap(body - velocityAngle)) / 0.9) : 0
            let spinRate = burning ? 24.0 : max(3.5, speed * 0.7)
            spin += spinRate * dt

            let rear = LetterPoint(
                x: position.x - forwardX * 5.4,
                y: position.y - forwardY * 5.4
            )
            let layingRubber = burning || sliding || slip > 0.34
            if layingRubber {
                skids.append(Skid(
                    time: time,
                    position: rear,
                    body: body,
                    strength: burning ? 0.85 : min(1, 0.45 + slip)
                ))
            }
            sincePuff += dt
            if layingRubber, sincePuff >= 0.045 {
                sincePuff = 0
                puffs.append(Puff(
                    time: time,
                    position: rear,
                    blowX: -forwardX * 7 + sideX * lateral * 0.35,
                    blowY: -forwardY * 7 + sideY * lateral * 0.35
                ))
            }

            samples.append(Sample(
                time: time,
                position: position,
                body: body,
                speed: speed,
                slip: max(slip, sliding ? 0.55 : 0),
                spin: spin,
                spinRate: spinRate,
                burning: burning,
                braking: braking,
                progress: anchor
            ))

            if let finish = path.last, anchor > 0.97, position.distance(to: finish) < 4 {
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
