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
