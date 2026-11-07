# Item models

Drop a model here as `<item id>.glb` and it replaces the built-in 3D item
when that item is used. Any size and position: the game scales it to fit
and centres it. It plays a quick 2-3 second animation with the item's
own sound (see `MOVES` and `PARTS` in `scripts/three/item_models.gd`).

Item ids: cigarettes, medicine, blank, saw, beer, magnifier, phone,
handcuffs, adrenaline, shakedown, switcheroo, bad_trade, chaos, spotlight,
flashbang, revolver, double_down, sticky_fingers, dumpster_dive,
garbage_day, tarot, joker_paint.

A part that should move on its own goes in as a separate object, named for
what it does: Cylinder (spins), Lid / Flap (opens), Plunger (pushes in),
Pin / Lever / Spoon (pops off), Blade (saws), Die / Dice (tumble),
Ring / Swirl (spins round).
