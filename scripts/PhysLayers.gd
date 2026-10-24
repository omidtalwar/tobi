class_name PhysLayers
## Physics layer bit values shared by every gameplay script.

const WORLD := 1    ## Layer 1: wooden walls, ramps, planks.
const BLOCKS := 2   ## Layer 2: tappable coloured blocks (raycast target).
const HAZARD := 4   ## Layer 3: rocks, boulder, lava balls.
const SENSOR := 8   ## Layer 4: reserved for areas.

## What hazard bodies collide with.
const HAZARD_MASK := WORLD | BLOCKS | HAZARD
