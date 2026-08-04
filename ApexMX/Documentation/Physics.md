# The physics model

The goal is a bike that is *believable*, not a bike that is accurate. A player
should be able to predict what will happen before it happens, and should always
be able to explain what just did.

Everything below is in SI units: metres, seconds, kilograms, newtons, radians.

## The body

The bike is a single planar rigid body carrying the chassis and the rider as
one sprung mass, with five degrees of freedom:

| State | Meaning |
|---|---|
| `position` | Centre of mass, metres |
| `velocity` | Linear velocity, m/s |
| `angle` | Chassis pitch; positive is nose-up |
| `angularVelocity` | Pitch rate, rad/s |
| `wheel.spinVelocity` | Each wheel's own spin, rad/s |

Wheel spin being a real degree of freedom is what makes wheelspin, lock-up and
engine braking fall out of the equations instead of needing special cases.

## Suspension

Each unit resolves its compression *kinematically*: solve for the compression
that would place the tyre exactly on the ground, then clamp it into the legal
stroke.

```
targetCompression = travel − (mountHeight − groundHeight − radius) / up.y
```

That constraint-first approach, rather than integrating a free unsprung mass,
is what keeps the suspension stable at the stiffness-to-timestep ratios a
motocross bike needs.

The resulting force is a spring plus an asymmetric damper:

- **Spring** — linear in compression, plus static preload.
- **Bump stop** — quadratic, engaging over the last 15% of travel. This is what
  turns a bottom-out into a firm thud rather than a rigid collision.
- **Damping** — compression and rebound coefficients differ, with rebound the
  higher of the two. That asymmetry is exactly what stops a real bike bucking
  after an impact, and it is the single most important number for how a machine
  *feels*.

The force is clamped at zero: a suspension unit can push, never pull. It is
applied at the mount point, so it produces both the vertical support and the
pitch torque. **Weight transfer is not scripted anywhere** — it emerges from
forces applied off the centre of mass.

## Tyres

Longitudinal force follows a saturating slip model:

```
slip  = (tyreSurfaceSpeed − groundSpeed) / max(|groundSpeed|, 2.5)
force = clamp(tyreStiffness × slip, ±μ × normalLoad)
```

Normalising against a floor speed keeps the model well-conditioned at a
standstill. The clamp is the friction circle: force rises linearly with slip
until grip runs out, then stops rising — it never collapses. That is what makes
losing traction progressive and recoverable rather than a cliff edge.

`μ` is the surface's coefficient × the tyre compound multiplier × the weather
grip scale. Normal load comes from the suspension, so grip genuinely depends on
how loaded the wheel is. Rolling resistance is a separate load-proportional
force opposing motion.

## Engine

Direct drive, no clutch: engine speed follows the rear wheel through the
overall ratio. The torque curve rises smoothly to peak, tapers above it, and
the limiter cuts drive to zero at redline. With the throttle shut the engine
drags on the drivetrain.

The consequence worth understanding: **in the air the rear wheel is free**, so a
throttle blip spins it up fast. Conservation of angular momentum pitches the
chassis nose-up in reaction. Braking that spinning wheel does the opposite.

## Air control

Three inputs, all with real trade-offs:

| Input | Effect | Cost |
|---|---|---|
| Lean | Direct rotational torque | None — but it is slow |
| Throttle | Nose up | Fuel, and wheel speed on landing |
| Rear brake | Nose down | Wheel speed on landing |

Rotation is damped so the bike does not spin indefinitely. A poor launch is
recoverable by a skilled rider, which is the point.

## Landings

A touchdown is judged on two quantities:

- **Impact** — closing speed along the ground normal.
- **Pitch error** — `|chassisAngle − slopeAngle|` at the contact point.

Below ~4 m/s of impact, any angle survives. Above it, the tolerated angular
error shrinks as impact rises. Soft surfaces widen the window (sand forgives,
concrete does not), as does suspension upgrade level.

Cross the threshold and the bike crashes, with a named reason — *cased the
landing*, *nosed in*, *looped out*, *hard impact* — and matching advice. A crash
is never mysterious.

## Integration

Semi-implicit Euler at a fixed 1/240 s: velocity first, then position. It is
far cheaper than RK4 and, unlike explicit Euler, does not pump energy into
spring systems — the property that matters most for a vehicle carried on two
springs. Non-finite state is caught and neutralised each step so a corrupt
replay or an extreme configuration cannot poison a session.

## Terrain

The ground is a uniformly sampled height field at 0.25 m spacing. Every query
the solver needs — height, gradient, normal, curvature, surface — is an O(1)
lookup with no broad phase, which is what makes running six riders at 240 Hz
affordable.

Gradients use a central difference rather than the containing segment's slope,
because a central difference is continuous across sample boundaries. A
discontinuous normal makes tyres chatter on ground that should be smooth.

Tracks are generated from an ordered feature list, deterministically, then
lightly smoothed — sharp corners where features meet are not a style problem,
they spike the suspension and can punch a wheel through the ground in one step.

## Tuning

Every number that shapes handling lives in `BikeSpec`, `SuspensionSpec`,
`EngineSpec` and `SurfaceType.Properties` — never in the solver. Retuning a
machine, adding a surface or shipping a new bike requires no change to
`BikePhysicsBody`.

## Extending it

The model was built to grow along these seams:

- **New surfaces** — add a `SurfaceType` case and its properties; traction,
  particles, audio and rolling resistance all pick it up.
- **Weather** — already multiplies grip through `environmentGrip`; wind would be
  an additional force in `applyAerodynamics`.
- **New machines** — data only.
- **Lateral dynamics** — the body is planar by design. A third dimension would
  extend `Vector2` rather than restructure the solver.

Any change that alters recorded outcomes must bump `GhostRun.currentPhysicsVersion`,
which retires incompatible ghosts instead of replaying them incorrectly.
