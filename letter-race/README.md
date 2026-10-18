# Letter Race

A first draft of Letter Race: each capital letter is a road, seen from above. A child presses the glowing car, traces that stroke, and the car drives the line they drew.

This version is an iPhone app. Open it in Xcode and run it on the simulator or on your phone. The first playable track is uppercase **A**. The home grid already lists A–Z and 0–9 so the next glyphs are data, not new screens.

## How A is written

Beginners are taught a print capital A as three separate strokes, every one starting where the pen goes down (Handwriting Without Tears: “big line slides down, big line slides down, little line across”):

1. From the top, down to the bottom-left foot
2. From the top, down to the bottom-right foot
3. The crossbar, left to right, where the middle of the letter meets the two legs

Each stroke is one car. The car waits on the start of that stroke. More than three wall hits — leaving the road, or clearly reversing along it — fails that stroke. Releasing inside the hatched finish, after the finger has actually traveled the road, sends the car along the line that was just drawn. When all three have finished, they drive again in order, and then the app says the letter is written.

## Run it

You need a Mac with Xcode 15 or newer.

**Simulator**

1. Open `letter-race/LetterRace.xcodeproj`.
2. Choose an iPhone simulator.
3. Press Run.

**Your iPhone**

1. Connect the phone and select it as the run destination.
2. In Signing, choose your Personal Team. The bundle id is `com.shuturminsky.letterrace`. A free Apple ID is enough for a week-long install.
3. On the phone, trust the developer certificate under Settings → General → VPN & Device Management.

The app targets iOS 17 and runs in portrait or landscape. Parental controls are not in this draft.

## Add a letter or a number

1. Describe the strokes in the same 0–100 space used by `LetterA` (y points down). One `LetterStroke` per pen-down: a centerline, and a finish gate on the last point.
2. In `GlyphCatalog`, set that glyph’s `track`.
3. Run the app. The tile changes from “Soon” to “Race”, and the race screen plays whatever track it is given.

Bridges, tunnels, and cursive can be added later as fields on a stroke. A does not use them.

## Tests

The road math and the catalog rule live in pure Swift. In Xcode, press Cmd+U.

On a machine without Xcode, from this directory:

```sh
swift test
```
