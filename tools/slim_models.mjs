// Copies the KayKit character models into models/characters/, keeping only
// the animations the game uses so the files stay small.
//
//   cd tools && npm install && node slim_models.mjs <folder with KayKit .glb files>
import { NodeIO } from "@gltf-transform/core";
import { prune, dedup, resample } from "@gltf-transform/functions";
import { readdirSync, mkdirSync } from "node:fs";
import { join, basename } from "node:path";

const KEEP = new Set([
  "Sit_Chair_Idle", "Sit_Chair_Pose", "Sit_Chair_StandUp", "Sit_Chair_Down",
  "Cheer", "Hit_A", "Death_A", "Death_A_Pose", "Idle", "Interact", "Use_Item", "Throw",
]);

const src = process.argv[2];
const out = new URL("../models/characters/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });
const io = new NodeIO();
for (const file of readdirSync(src).filter((f) => f.endsWith(".glb"))) {
  const doc = await io.read(join(src, file));
  for (const anim of doc.getRoot().listAnimations()) {
    if (!KEEP.has(anim.getName())) anim.dispose();
  }
  // drop keyframes that a straight line between their neighbours would give
  await doc.transform(resample({ tolerance: 1e-3 }), prune(), dedup());
  await io.write(join(out, basename(file)), doc);
  console.log("wrote", file);
}
