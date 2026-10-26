# The test suite, measured (2026-10-26)

## Where the time went before

### GitHub, release v0.19.0 (run 40265991947, the one that passed)

| Part | Time |
| --- | --- |
| Checkout (3.8 GB of `queue/audits` pictures came along) | 3.2 min |
| Compiling, inside Run tests | 734 s (12.2 min) |
| XCTest | about 1 s |
| swift-testing, one test at a time (`--no-parallel`) | 2,365 s (39.4 min) |
| Legibility check | 55 s |
| **Run tests step** | **53.2 min** |
| Build app (release, from scratch) | 14.3 min |

The next v0.19.0 run timed out at 65 minutes in Run tests. Of the 2,372 s of
test time, 230 tests over a second each were 2,184 s; the other 14,375 tests
were about 190 s together.

### This Mac, at the start

`Scripts/test.sh`: 539 s and **parked** (exit 4) in text reads and HEIC
writes. Cause, reproduced 3 of 3: on macOS 27.0.1 a Vision text read never
answers while every Swift pool thread is blocked, even on its own
userInitiated thread (drill: answered with the pool free, silent for 20 s with
it full). The test that holds this, `TextReadsOnAFullPoolTests`, hung 3 of 3
alone. After the fix: 401 s green.

## The slowest tests, one at a time

Measured with `swift test --skip-build --no-parallel --filter <suite>`.
"GitHub" is the serial v0.19.0 run, the same thing on the 3 core VM.

| Test or suite | GitHub | This Mac before | This Mac after | What changed |
| --- | --- | --- | --- | --- |
| Words travelling into a title, every entrance (9 cases) | 218 s | 33.1 s | 10.6 s | "Ship" by letter, not 15 letters; cases may run side by side |
| A busy MP4 lands at the size the sheet said (suite) | 241 s | 158.7 s | 36.4 s | long files at 640x400; stop at the first write that lands where it should |
| A long recording, quiet then busy | 40.6 s | 27.5 s | 4.5 s | same |
| A document's weigh is what lands (3 cases) | 122 s | 84 s | 13.7 s | same |
| Misalignment corpus (suite) | 171 s | 88.7 s | 9.3 s | one scan of the corpus, spread over the cores, shared; picture check decodes |
| Known type size read back (two tests) | 41 + 41 s | 21.4 + 21.2 s | 3.1 + 3.0 s | the 18 reads spread over the cores |
| Settings pane rows read at 13 / 26 | 26 + 24 s | 12.7 + 12.8 s | 3.1 + ~3 s | page read spread over the cores |
| Callouts on a real capture (suite) | 136 s | 65.9 s | ~21 s | elements under each gap found once for three sweeps |
| Separating the capture quickly (prints only) | 36 s | 23.5 s | off | asserts nothing; runs with `PHOTONZ_PERF=1` |
| Separate over a whole screenshot (suite) | 35 s | 33.5 s | 10.1 s | the 200-run page separated once |
| Pieces each fixture makes (suite) | 58 s | 31.1 s | 12.2 s | each fixture taken apart once |
| A calm redline (suite) | 53 s | 26.7 s | 2.4 s | four screens read once, not sixteen times |
| Reading a separated run back (suite) | 125 s | 74.4 s | 30.1 s | duplicate weight/size test merged; reads spread |
| Animated export written twice | 68 s | 54.2 s | 28.1 s | the longer clip 4 s, not 6 |

Still over ten seconds on their own here: the animated export written twice
(28 s), Agent find_elements on the settings screenshot (22 s, the app's own
element scan in a debug build), Separate into Layers on a whole app window
(22 s, one shared separation), the boxed-in caliper sweep (about 16 s, mostly
the shared gap grid, 36 ms per gap read in a debug build), and the first test
of "Reading a separated run back" (12 s, the shared page read).

## Removed or merged

- `settlingTheSizeNeverCostsAReading` (ReadRunAsTextFixtureTests): the same
  nine reads and the same count as `settlingTheWeightNeverCostsAReading`.
  Merged into `settlingTheWeightOrTheSizeNeverCostsAReading`; that test still
  covers both promises.
- `separatingTheCaptureIsQuickEnoughToFeelLikeACommand`: prints a timing,
  asserts nothing. Runs with `PHOTONZ_PERF=1`, like its 12 MP neighbour.
- `corpusIsWhole` no longer analyses every picture to prove it loads; it
  decodes each one. The analysis it threw away is what the two bar tests
  measure.

## After

| | Before | After |
| --- | --- | --- |
| `Scripts/test.sh` on this Mac, build warm | 539 s parked, then 401 s | 262 s |
| GitHub checkout | 3.2 to 3.9 min | 15 s |
| GitHub build, nothing kept | 12.2 min in Run tests (+4.5 min build step) | 18.9 min (one step, tests included) |
| GitHub build, kept, 11 test files changed | (no cache) | 4.7 min; restore 21 s, cache 597 MB |
| GitHub swift-testing | 2,365 s one at a time | 1,445 s, two at a time |
| GitHub Run tests step | 53.2 min | 25.8 min, green |
| GitHub release bundle build, nothing kept | 14.3 min | 14.3 min (860 s); now kept |

On GitHub the suites that run one test at a time finish last, each at about
1,400 s of the 1,445: "A busy MP4 lands at the size the sheet said", "Reading
a separated run back into words", "Turning in depth, as drawn", "The weight
and size a page of labels comes back in", "Text turning in depth is drawn in
perspective". With two tests at a time on three cores, every step of such a
suite waits behind the queue. That is the next thing to cut.

## Pass 2 (evening): three slices on three runners

One GitHub runner has three cores. On the green run 40368389297 the whole
suite was 1,267 s of tests at two at a time, and on this Mac the targets cost
Render 1,593 CPU s, Core 380, Media 80 in one run each: CPU-bound, so no
ordering gets one runner under 15 minutes. `Scripts/test.sh --shard K/N` runs
one of N slices; every suite type goes to exactly one slice, heaviest first to
the lightest, by `Scripts/test-weights.tsv` (each suite measured alone by
`Scripts/test-weights.sh`). The slices sum to exactly 14,604 tests, here and
on GitHub.

| | Before | After |
| --- | --- | --- |
| CI Run tests (one runner, two at a time) | 22.6 min (40368389297) | 7.4 / 6.6 / 8.0 min (40417574675); 7.2 / 8.9 / 8.2 (40419872948) |
| CI slices' own test time | 1,267 s | 338 / 374 / 446 s, 5,184 + 4,837 + 4,583 tests |
| Release workflow, whole | 53 min of tests, then build and notarize (v0.19.0) | 9.5 min, dry run 40421624172: slices 6.1 / 8.4 / 7.3 min beside build + sign + notarize + DMG in 3.0 min |
| Debug build from the kept folder, no source change | 4 to 6 min (the folder was saved after a release build in it) | 13 to 22 s (40421624172) |
| Release app build from the kept folder | 4.2 min | 27 s in release.yml, 1.5 min in CI |
| Local slices, CPU s | dealt by name: 366 / 560 / 821 | by weight: 590 / 680 / 826 |

What changed in the workflows: ci.yml runs three test slices beside a bundle
job (the queue's checks, the release bundle). release.yml runs three test
slices beside the build, sign and package job, and a Linux job publishes when
both are through; `dry_run=true` times all of it and publishes nothing. Each
configuration keeps its own build (`build-debug-…` saved by slice 1 right
after it builds, `build-release-…` by the bundle job). CI skips commits named
`release: v…`, which release.yml tests on the tag, so a release is not
queueing for runners behind CI.

Three green CI runs in a row, all in parallel: 40368389297, 40417574675,
40419872948.

Slice 3 still runs about a minute longer than the others: the text-reading
suites (ReadSizeGroundTruth, ReadRunAsTextFixture, ReadPageWeightFixture) cost
far more CPU inside a full run than measured alone.

### Tests over ten seconds alone, after pass 2

Measured with `swift test --skip-build --no-parallel --filter <suite>`:

| Test | Alone | Why |
| --- | --- | --- |
| written twice, a GIF is the same file and a HEIC the same pictures | 36 s -> 6.0 s | clips, formats and presets now run side by side |
| aWholeWindowGivesUpItsBoxesAndNotJustItsWords | 21.7 s | the suite's one shared separation of a 2x whole window, debug build |
| Every control a redliner measures is listed once | 21.5 s | the app's element scan of the settings screenshot, debug build |
| everyBoxedInCaliperOnTheCaptureKeepsTheClassicSpot | 16 to 18 s | 13.6 s is the shared 864-point gap grid; spreading it over the cores did not shorten it, so the cost is inside each core gap read (reverted, not shipped) |
| A document's weigh is what lands, busy or quiet (3 cases) | 14.5 s | about 5 s a case |
