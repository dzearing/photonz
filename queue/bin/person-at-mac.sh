#!/bin/bash
# Whether a person is using this Mac right now, from how long it has been since
# the last keyboard, mouse or trackpad input (IOHIDSystem's HIDIdleTime).
#
# Walks drive the probe app, and on 2026-09-26 the user reported that while the
# loop tested, their machine was unusable: they could not type, and saying
# "stop testing" took pulling focus back five times. So nothing that drives the
# probe starts while somebody is at the keyboard, and a walk that is running
# stops the moment they touch it. Walks themselves never move the real cursor
# or post events through the HID system (PlaytestPointer.swift), so only a
# person resets this clock.
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
