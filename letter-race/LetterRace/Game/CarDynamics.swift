import Foundation

/// A toy car with traction. It does not stick to the ink.
/// The rear wheels spin in place at the start, then the car rolls.
/// A tight corner asks for more yaw than the tires can give, so the rear steps out.
struct CarSimulation: Equatable {
    /// Time the rear tires smoke before the car takes off.
    static let burnout = 0.62
    /// Extra time after the drawn stroke so a slide can hook back onto the finish.
    static let settle = 0.28

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

    static func driveDuration(drawn: Double) -> Double {
        burnout + max(drawn, 0.35) + settle
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

    static func run(path: [LetterPoint], drawn: Double) -> CarSimulation {
        let drawn = max(drawn, 0.35)
        let total = RoadGeometry.length(of: path)
        let duration = driveDuration(drawn: drawn)
        guard path.count >= 2, total > 1, let initial = RoadGeometry.heading(of: path, at: 0) else {
            let only = path.first ?? LetterPoint(x: 50, y: 50)
            let still = Sample(
                time: 0, position: only, body: 0, speed: 0, slip: 0, spin: 0, spinRate: 0,
                burning: false, braking: false, progress: 1
            )
            return CarSimulation(duration: duration, cruise: 0, samples: [still], skids: [], puffs: [])
        }

        let cruise = total / drawn
        let dt = 1.0 / 60.0
        var position = path[0]
        var body = atan2(initial.y, initial.x)
        var speed = 0.0
        var lateral = 0.0
        var spin = 0.0
        var samples: [Sample] = []
        var skids: [Skid] = []
        var puffs: [Puff] = []
        var sincePuff = 1.0
        var time = 0.0

        while time <= duration + 0.0001 {
            let burning = time < burnout
            let driven = max(0, time - burnout)
            let targetProgress = min(1, driven / drawn)
            let lookAhead = min(1, targetProgress + (8.5 + speed * 0.05) / total)
            let look = RoadGeometry.point(at: lookAhead, along: path)
            let desired = atan2(look.y - position.y, look.x - position.x)
            let steer = clamp(wrap(desired - body), -0.95, 0.95)

            let wheelbase = 8.0
            let demandedYaw = speed / wheelbase * tan(steer)
            let maxYaw = burning ? 0.7 : 2.6
            let yaw = clamp(demandedYaw, -maxYaw, maxYaw)
            body = wrap(body + yaw * dt)

            let here = RoadGeometry.heading(of: path, at: targetProgress) ?? initial
            let ahead = RoadGeometry.heading(of: path, at: min(1, targetProgress + 16 / total)) ?? here
            let roadTurn = wrap(atan2(ahead.y, ahead.x) - atan2(here.y, here.x))
            let sliding = !burning && abs(roadTurn) > 0.42 && speed > 6
            if sliding {
                let outward: Double = roadTurn > 0 ? -1 : 1
                let wanted = outward * min(12, abs(roadTurn) * 8)
                lateral += (wanted - lateral) * min(1, 10 * dt)
            } else if !burning {
                lateral *= max(0, 1 - 5.5 * dt)
            }
            lateral = clamp(lateral, -12, 12)
            if burning {
                lateral *= max(0, 1 - 4 * dt)
            }

            let wantedSpeed = burning ? min(7.5, cruise * 0.16) : (targetProgress >= 1 ? 0 : cruise)
            let accel = burning ? 12.0 : max(80, cruise * 3.2)
            speed += clamp(wantedSpeed - speed, -accel * dt, accel * dt)
            if targetProgress >= 0.94 {
                speed *= max(0, 1 - 6 * dt)
                lateral *= max(0, 1 - 8 * dt)
            }

            let forwardX = cos(body)
            let forwardY = sin(body)
            let sideX = -sin(body)
            let sideY = cos(body)
            var velocityX = forwardX * speed + sideX * lateral
            var velocityY = forwardY * speed + sideY * lateral

            let nearest = RoadGeometry.project(position, onto: path, near: targetProgress)
            let off = nearest.distance
            var pull = burning ? 0.35 : (sliding ? 1.8 : 5.2)
            if off > 9 { pull += (off - 9) * 0.9 }
            if targetProgress > 0.93 { pull += 4 }
            velocityX += (nearest.closest.x - position.x) * pull * dt
            velocityY += (nearest.closest.y - position.y) * pull * dt

            position.x += velocityX * dt
            position.y += velocityY * dt

            let settled = RoadGeometry.project(position, onto: path, near: targetProgress)
            if settled.distance > 8.2 {
                let keep = 8.2 / settled.distance
                position.x = settled.closest.x + (position.x - settled.closest.x) * keep
                position.y = settled.closest.y + (position.y - settled.closest.y) * keep
                lateral *= 0.7
            }

            if targetProgress >= 1, let finish = path.last {
                let catchUp = min(1, 7 * dt)
                position.x += (finish.x - position.x) * catchUp
                position.y += (finish.y - position.y) * catchUp
            }

            let velocityAngle = atan2(velocityY, velocityX)
            let moving = hypot(velocityX, velocityY) > 1
            let slip = moving ? min(1, abs(wrap(body - velocityAngle)) / 0.9) : 0
            let spinRate = burning ? 24.0 : max(3.5, speed * 0.7)
            spin += spinRate * dt
            let braking = targetProgress > 0.9 && !burning

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

            let progress = RoadGeometry.project(position, onto: path, near: targetProgress).progress
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
                progress: progress
            ))
            time += dt
        }

        return CarSimulation(duration: duration, cruise: cruise, samples: samples, skids: skids, puffs: puffs)
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
