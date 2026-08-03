# Track Rush

A side-scrolling physics motocross racer for iOS, in the tradition of Trials and
Mad Skills: throttle, brake, and shift your weight over ten hand-tuned tracks.
Land it wrong and you start again.

## Riding

- **GAS** — torque to the rear wheel. Wheelspin, hills, and bad landings all
  eat acceleration, so it is not a "hold to win" button.
- **BRAKE** — slows you, then reverses once you are nearly stopped.
- **LEAN BACK / FWD** — rotates the bike. Weak on the ground where it shifts
  weight over a wheel, strong in the air where it is your only rotation control.

Touch the ground with anything except a wheel and the run ends.

## How it works

Tracks are generated from a seeded value-noise function, so track 4 is the same
track 4 on every device and every run — times are comparable and a track you
learn stays learned. Ramps are raised cosines carved into that terrain with a
steeper leading edge, which makes them launch you rather than trip you. The
same sample set feeds both the drawn ground and the physics edge chain, so what
you see is exactly what you collide with.

The bike is a chassis body with two wheels on rigid pin joints. Real spring
suspension wobbles badly at this scale, so the arcade feel comes from mass
distribution and damping instead. Ground contact is tested with a short ray
under each wheel rather than contact callbacks — steadier for something checked
every frame, and it means a couple of frames of daylight on a bumpy straight
does not count as being airborne.

Best times are stored per track, and finishing one unlocks the next.

## Building

Open `TrackRush.xcodeproj` and run, or take the unsigned `.ipa` from the repo's
`latest` release. Landscape, iOS 16+.
