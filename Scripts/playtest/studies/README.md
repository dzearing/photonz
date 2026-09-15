# Study walks

Walks kept out of the sweep on purpose. `Scripts/playtest-all.sh` and
`queue/bin/sweep.sh` both glob `Scripts/playtest/*.json`, which does not reach
this folder, so nothing in here runs in the 322-walk set.

A walk belongs here when it **measures** rather than **asserts**: it exists to
read numbers out of the running app for a study, and it has no claim that could
fail. A walk with a `waitFor` or an `expect` in it is a regression check and
belongs one folder up.

Run one the usual way:

```
Scripts/playtest.sh Scripts/playtest/studies/side-pane-load-walk.json --no-build
```

| Walk | What it measures | Written for |
| --- | --- | --- |
| `side-pane-load-walk.json` | The right hand dock's section offsets, viewport height and which sections are whole on screen, at 1000x640, 1200x720 and 1680x1000 | `work-out-whether-the-right-hand-pane-is-carrying`, 2026-09-15 |
