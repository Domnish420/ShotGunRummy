# Shotgun Party: item card art prompts

The item cards are **playing cards first**. The game draws the card itself: its
black body, purple border, a thin inner frame, the item "suit" star in two
corners, and a gold-framed panel in the middle. Your art is **only the
picture that goes in that panel**, like the portrait on a King or Queen.

So for each item, ask Gemini for **one square picture, 512 x 512 px, no text**,
and save it as the file name shown (e.g. `beer_art.png`) for
`textures/items/`. There's **no name on the card**: the picture alone has to
say what the item is, at a glance, even small in your hand.

Paste the **style block** first, then one card's prompt.

## Style block (use with every card)

> A square 512 x 512 in-game item icon rendered in the style of a PlayStation 2
> game from around 2002. It must look like real-time 3D from that console,
> not a photo and not a modern render: a low-polygon model with visible flat
> faces and hard edges, small blurry low-resolution textures (about 128 pixels
> wide, slightly smeared and pixelated when close), simple vertex lighting
> from one warm overhead lamp, hard-edged shadows, no reflections or
> ray-tracing, no depth of field, no film grain, slightly jagged edges (no
> anti-aliasing), muted colours with a little colour banding. Like an item
> pickup or inventory icon from an early-2000s survival horror or crime game.
> ONE object, big and centred, filling most of the square, seen from a slight
> three-quarter angle so its shape is instantly recognisable as a silhouette.
> Plain near-black background (#120d10) with a soft purple rim light on the
> object. Absolutely no text, letters, numbers, logos, labels, borders or
> frames, and no people.

If it still comes out too realistic, add: *"Lower the polygon count, blur the
textures, flatten the lighting: it should look like a 2002 game asset, not a
photograph."*

## The pictures

Each one is described as the one object that says what the card does. Keep it
simple: if you can't tell what it is from a thumbnail, it isn't working.

**1. `cigarettes_art.png`** (gain 1 health)
> A crumpled soft pack of cigarettes with two sticking out, one lit with a
> curl of smoke.

**2. `medicine_art.png`** (50/50: heal 2 or lose 1)
> A brown pill bottle tipped over, spilling red-and-white capsules, with a
> sickly green tint.

**3. `blank_art.png`** (the next shot does no damage)
> A single shotgun shell standing upright, its hull white and hollow, a dud
> with a little puff of dust instead of smoke.

**4. `saw_art.png`** (the next shell deals double damage)
> A rusty hand saw with a wooden handle, its teeth glinting.

**5. `beer_art.png`** (burn the top card)
> A brown beer bottle with a foaming top, unlabelled.

**6. `magnifier_art.png`** (secretly look at the top card)
> A brass magnifying glass with a bright glint on the lens.

**7. `phone_art.png`** (see a card in someone's hand)
> A cheap scuffed flip phone, open, its little screen glowing green.

**8. `handcuffs_art.png`** (someone skips their next turn)
> A pair of steel handcuffs, cuffs closed, the chain hanging between them.

**9. `adrenaline_art.png`** (steal an item)
> A syringe full of glowing neon-yellow liquid, a drop at the needle tip.

**10. `shakedown_art.png`** (someone throws away a random card)
> A clenched fist in a leather glove, knuckles forward, punching.

**11. `switcheroo_art.png`** (swap whole hands)
> Two curved arrows chasing each other in a circle, made of chunky metal, one
> red and one blue.

**12. `bad_trade_art.png`** (swap 2 random cards)
> A handshake between two gloved hands, one hand's fingers crossed behind.

**13. `chaos_art.png`** (everyone passes their hand left)
> A swirling purple tornado, spinning.

**14. `spotlight_art.png`** (someone's hand is shown to everyone)
> A theatre spotlight lamp on a stand, its beam blasting white light.

**15. `flashbang_art.png`** (everyone else shows 2 cards)
> A stun grenade, its pin pulled, going off in a white flash.

**16. `revolver_art.png`** (play or Russian roulette)
> An old six-shooter revolver with its cylinder swung open, one bullet in it.

**17. `double_down_art.png`** (someone must draw 2 cards)
> A pair of red dice, both showing double sixes.

**18. `sticky_fingers_art.png`** (steal a card from a meld)
> An open hand dripping with gold honey, sticky strands between the fingers.

**19. `dumpster_dive_art.png`** (take the top 3 discards)
> A small green dumpster with its lid propped open, rubbish poking out.

**20. `garbage_day_art.png`** (someone takes the whole discard pile)
> A dented metal trash can tipped on its side, rubbish spilling out.

**21. `tarot_art.png`** (the trump moves to the next rank)
> A glowing crystal ball on a little brass stand, purple mist inside.

**22. `joker_paint_art.png`** (a card becomes wild)
> A jester's mask, half grinning, painted in bright splashes of colour.

## Tips

- Generate a few and pick the most PS2-looking one; keep using the same style
  block so the set matches.
- Ask for a square image. The game puts it in the card's panel, so anything
  near the very edge may be trimmed; keep the object in the middle.
- No text anywhere in the picture. If Gemini adds some, say "remove all text".

## Board game box lids

Each board game on the party room shelf is a box with its lid art facing the
room. Ask for one square picture, 512 x 512 px, and save it as
`textures/boxes/<game>.png`. Lid art **has the game's name in it** (it's the
box's logo), so when the file's there the game doesn't print its own name over
it. With no file, the game paints a lid and puts the name on itself.

**`timber.png`** (TIMBER, the tower game)
> Board game box lid art, square, in the style of a PlayStation 2 era game
> from around 2002: low-polygon 3D with flat faces and hard edges, small
> blurry low-resolution textures, simple warm lighting, slight colour banding,
> no modern photo-realism. A tall tower of pale pine wooden blocks stacked in
> alternating layers of three, standing on a dark wooden table, lit by one
> warm spotlight from above. One block sticks halfway out of the middle of the
> tower and another is tumbling off the top. Behind it, a smoky dark red-brown
> saloon background with a faint purple glow. Across the top of the lid, the
> word "TIMBER" in big chunky blocky letters made of the same pale wood, with
> dark outlines, slightly 3D. Only that one word: no exclamation mark, no
> other text, no numbers, no logos, no borders.

If the letters come out wrong, ask again with: *"Spell it exactly T-I-M-B-E-R,
one word, no punctuation."* Or ask for the art with **no text at all**, save
that instead, and tell me: I'll switch the box back to printing the name over
it.
