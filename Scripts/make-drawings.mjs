#!/usr/bin/env node
// Builds the drawing set Ask draws from (Resources/Drawings/drawings.json):
// the Twemoji graphics (CC-BY 4.0, Resources/Drawings/LICENSE-GRAPHICS.txt)
// for every everyday thing in Unicode's emoji list, named and given the words
// people use for them from CLDR. People, flags and signs are left out: Ask
// draws things, not symbols.
//
//   npm pack @twemoji/svg@15.0.0 && tar xzf twemoji-svg-15.0.0.tgz   # -> package/*.svg
//   curl -O https://unicode.org/Public/emoji/15.1/emoji-test.txt
//   curl -o annotations.json https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json
//   node Scripts/make-drawings.mjs <package dir> <emoji-test.txt> <annotations.json>
//
// Run it only to change the set; the result is committed.
import fs from "node:fs";
import path from "node:path";

const [svgDir, testFile, annotationsFile] = process.argv.slice(2);
if (!svgDir || !testFile || !annotationsFile) {
  console.error("usage: node Scripts/make-drawings.mjs <twemoji svg dir> <emoji-test.txt> <annotations.json>");
  process.exit(2);
}
const annotations = JSON.parse(fs.readFileSync(annotationsFile, "utf8")).annotations.annotations;

const groups = new Set(["Smileys & Emotion", "Animals & Nature", "Food & Drink", "Travel & Places", "Activities", "Objects"]);
// In Smileys & Emotion only the faces and hearts are drawings of a thing.
const smileySubgroups = /^(face-|heart|cat-face|monkey-face)/;

// The everyday word for a thing where Unicode's name is not it ("car" is
// "automobile", a cup of coffee is "hot beverage"), and the one drawing a
// word means when several carry it.
const aliases = {
  "🙂": ["smiley", "smiley face", "smile", "smiling face", "happy face", "face"],
  "☕": ["coffee", "coffee cup", "cup of coffee", "cup", "mug", "coffee mug", "tea", "cup of tea", "hot drink"],
  "🚗": ["car", "automobile"], "🐕": ["dog", "puppy", "hound"], "🐈": ["cat", "kitten", "kitty"],
  "🏠": ["house", "home"], "🌳": ["tree"], "🌲": ["pine tree", "fir tree", "christmas tree"],
  "🌼": ["flower", "daisy"], "🐦": ["bird"], "🐟": ["fish"], "🚲": ["bicycle", "bike"],
  "🌄": ["sun over mountains", "sunrise over mountains", "sunset over mountains", "mountains with sun", "sunrise", "landscape"],
  "⛰️": ["mountain", "mountains"], "☀️": ["sun", "sunshine"], "⭐": ["star"], "❤️": ["heart", "love heart"],
  "🚀": ["rocket", "rocket ship", "spaceship"], "✈️": ["plane", "airplane", "aeroplane", "jet"],
  "🍎": ["apple"], "🎂": ["cake", "birthday cake"], "🎁": ["gift", "present"], "📷": ["camera"],
  "💡": ["light bulb", "lightbulb", "idea"], "🌙": ["moon"], "☁️": ["cloud"], "🌈": ["rainbow"],
  "🐎": ["horse"], "⚽": ["ball", "football", "soccer ball"], "🎈": ["balloon"], "🔑": ["key"],
  "📖": ["book"], "✏️": ["pencil"], "⏰": ["clock", "alarm clock"], "⛵": ["boat", "sailboat", "sailing boat"],
  "🚆": ["train"], "🚚": ["truck", "lorry"], "🏰": ["castle"], "🚢": ["ship"], "🍔": ["burger", "hamburger"],
  "🐢": ["turtle", "tortoise"], "🦋": ["butterfly"], "🐝": ["bee"], "🐞": ["ladybug", "ladybird"],
  "🍦": ["ice cream"], "🍩": ["donut", "doughnut"], "🍪": ["cookie", "biscuit"], "🍕": ["pizza"],
  "🎸": ["guitar"], "🎵": ["music", "music note", "note"], "🏆": ["trophy", "cup trophy"], "👑": ["crown"],
  "🔥": ["fire", "flame"], "💧": ["drop", "water drop", "droplet"], "⚡": ["lightning", "lightning bolt", "bolt"],
  "❄️": ["snowflake"], "☂️": ["umbrella"], "🌵": ["cactus"], "🍄": ["mushroom"], "🌻": ["sunflower"],
  "🌹": ["rose"], "🌷": ["tulip"], "🐘": ["elephant"], "🦁": ["lion"], "🐻": ["bear"], "🐼": ["panda"],
  "🐧": ["penguin"], "🦊": ["fox"], "🐰": ["rabbit", "bunny"], "🐭": ["mouse"], "🐸": ["frog"],
  "🦉": ["owl"], "🐙": ["octopus"], "🐳": ["whale"], "🐬": ["dolphin"], "🦈": ["shark"], "🐍": ["snake"],
  "🦄": ["unicorn"], "🐉": ["dragon"], "🐄": ["cow"], "🐖": ["pig"], "🐑": ["sheep", "lamb"], "🐔": ["chicken", "hen"],
  "🦆": ["duck"], "🐒": ["monkey"], "🦒": ["giraffe"], "🦓": ["zebra"], "🐅": ["tiger"],
  "🍌": ["banana"], "🍓": ["strawberry"], "🍉": ["watermelon"], "🍇": ["grapes"], "🍋": ["lemon"],
  "🥕": ["carrot"], "🍞": ["bread"], "🧀": ["cheese"], "🍰": ["slice of cake"], "🍷": ["wine", "wine glass"],
  "🍺": ["beer"], "🍵": ["teacup", "green tea"], "🥤": ["soda", "cup with straw"],
  "🏡": ["house with garden", "cottage"], "🏢": ["office", "office building", "building"], "🏫": ["school"],
  "🏥": ["hospital"], "⛪": ["church"], "🗼": ["tower"], "🌉": ["bridge"], "🏖️": ["beach"], "🏝️": ["island"],
  "🌋": ["volcano"], "⛺": ["tent", "camping"], "🚌": ["bus"], "🚑": ["ambulance"], "🚒": ["fire engine", "fire truck"],
  "🚓": ["police car"], "🚕": ["taxi", "cab"], "🏍️": ["motorcycle", "motorbike"], "🛴": ["scooter"],
  "🚁": ["helicopter"], "🛸": ["ufo", "flying saucer"], "⚓": ["anchor"], "🎃": ["pumpkin", "jack o lantern"],
  "🎄": ["christmas tree"], "🎉": ["party", "party popper", "confetti"], "🎨": ["palette", "paint palette"],
  "📱": ["phone", "mobile phone", "smartphone", "iphone"], "💻": ["laptop", "computer"], "🖥️": ["desktop computer", "monitor"],
  "⌚": ["watch"], "📺": ["tv", "television"], "🔔": ["bell"], "📌": ["pin", "pushpin"], "✂️": ["scissors"],
  "🔒": ["lock", "padlock"], "🔨": ["hammer"], "🔧": ["wrench", "spanner"], "⚙️": ["gear", "cog", "settings"],
  "💰": ["money bag"], "💎": ["diamond", "gem"], "🎓": ["graduation cap"], "👓": ["glasses"], "🎒": ["backpack"],
  "📦": ["box", "package", "parcel"], "✉️": ["envelope", "letter", "mail"], "📅": ["calendar"], "🔍": ["magnifying glass", "search"],
  "🧸": ["teddy bear", "teddy"], "🎮": ["game controller", "controller"], "🎯": ["target", "bullseye"],
  "🏀": ["basketball"], "🎾": ["tennis ball"], "🌍": ["earth", "globe", "world"], "🪐": ["planet", "saturn"],
  "🌊": ["wave", "ocean", "sea"], "🍀": ["clover", "four leaf clover", "shamrock"], "🍁": ["maple leaf", "leaf"],
  "😀": ["grin", "grinning face", "big smile"], "😢": ["sad face", "crying face"], "😂": ["laughing face"],
  "😍": ["heart eyes"], "😎": ["cool face", "sunglasses face"],
};

const strip = (s) => s.replace(/️/g, "");
const aliasByStripped = Object.fromEntries(Object.entries(aliases).map(([k, v]) => [strip(k), v]));

let group = "", subgroup = "";
const entries = [];
const missing = [];
for (const line of fs.readFileSync(testFile, "utf8").split("\n")) {
  if (line.startsWith("# group:")) { group = line.slice(8).trim(); continue; }
  if (line.startsWith("# subgroup:")) { subgroup = line.slice(11).trim(); continue; }
  const m = line.match(/^([0-9A-F ]+);\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$/);
  if (!m || !groups.has(group)) continue;
  if (group === "Smileys & Emotion" && !smileySubgroups.test(subgroup)) continue;
  const points = m[1].trim().split(/\s+/).filter((p) => p !== "FE0F");
  if (points.length !== 1) continue; // sequences: skin tones, ZWJ mixes
  const emoji = m[2];
  const file = path.join(svgDir, points[0].toLowerCase() + ".svg");
  if (!fs.existsSync(file)) { missing.push(m[3]); continue; }
  const svg = fs.readFileSync(file, "utf8").trim().replace(/\s+xmlns:xlink="[^"]*"/, "");
  const ann = annotations[emoji] ?? annotations[strip(emoji)] ?? {};
  const name = (ann.tts?.[0] ?? m[3]).toLowerCase();
  const words = (ann.default ?? []).map((w) => w.toLowerCase()).filter((w) => w !== name);
  const entry = { n: name, w: words, s: svg };
  const extra = aliasByStripped[strip(emoji)];
  if (extra) entry.a = extra;
  if (group === "Smileys & Emotion" && subgroup.startsWith("face-")) entry.f = true;
  entries.push(entry);
}
const out = {
  about: "Twemoji graphics by Twitter, Inc and other contributors (https://github.com/jdecked/twemoji), licensed under CC-BY 4.0 (LICENSE-GRAPHICS.txt). Names and words from Unicode CLDR. Built by Scripts/make-drawings.mjs.",
  drawings: entries,
};
const target = path.join(path.dirname(new URL(import.meta.url).pathname), "..", "Resources", "Drawings", "drawings.json");
fs.writeFileSync(target, JSON.stringify(out));
const unknownAliases = Object.keys(aliasByStripped).filter((k) => !entries.some((e) => e.a === aliasByStripped[k]));
console.log(`${entries.length} drawings, ${(fs.statSync(target).size / 1e6).toFixed(2)} MB -> ${target}`);
if (missing.length) console.log(`no graphic for ${missing.length}: ${missing.slice(0, 8).join(", ")}`);
if (unknownAliases.length) console.log(`aliases with no drawing: ${unknownAliases.join(" ")}`);
