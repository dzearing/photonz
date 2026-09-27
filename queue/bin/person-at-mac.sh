#!/bin/bash
# Whether a person is using this Mac right now, from how long it has been since
# the last keyboard, mouse or trackpad input (IOHIDSystem's HIDIdleTime).
#
# Walks drive the probe app, and on 2026-09-26 the user reported that while the
# loop tested, their machine was unusable: they could not type, and saying
# "stop testing" took pulling focus back five times. That was fixed in the
# harness and the app, and queue/bin/focus-drill.sh measured every walk clean
# the same evening, so an ordinary walk now runs while somebody works. What
# still asks this script, and waits or stops for the person:
#   - a walk that needs the Mac to itself (queue/bin/walk-needs-the-mac.mjs:
#     a picture of an open menu, a real drag, or `setup.front`), in
#     Scripts/probe-app.sh and Scripts/playtest.sh: each takes every key;
#   - Scripts/probe-app.sh with no walk: it brings the app to the front;
#   - the whole walk set (queue/bin/sweep.sh due and run), two hours of it;
#   - the focus drill itself, whose stand-in for the person takes the front.
# Walks themselves never move the real cursor or post events through the HID
# system (PlaytestPointer.swift), so only a person resets this clock.
#
#   queue/bin/person-at-mac.sh idle          seconds since the last input
#   queue/bin/person-at-mac.sh away <secs>   exit 0 when idle at least that long
#   queue/bin/person-at-mac.sh here <secs>   exit 0 when input came in the last <secs>
#
# PHOTONZ_IGNORE_PERSON=1 makes `away` always true and `here` always false, for
# a person who runs a walk by hand and wants it to run while they watch.
idle() {
  ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'
}
case "${1:-idle}" in
  idle) s=$(idle); echo "${s:-0}" ;;
  away)
    [[ "${PHOTONZ_IGNORE_PERSON:-0}" == 1 ]] && exit 0
    s=$(idle); [[ -n "$s" ]] || exit 0   # no reading: never block on it
    (( s >= ${2:-120} )) ;;
  here)
    [[ "${PHOTONZ_IGNORE_PERSON:-0}" == 1 ]] && exit 1
    s=$(idle); [[ -n "$s" ]] || exit 1
    (( s < ${2:-3} )) ;;
  *) echo "usage: person-at-mac.sh idle|away <secs>|here <secs>" >&2; exit 2 ;;
esac
