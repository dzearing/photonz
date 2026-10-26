#!/bin/bash
# Gives every tracked file a modification time that comes from its CONTENT, so
# a build folder kept from an earlier checkout is reused for every file that
# has not changed.
#
# A fresh checkout stamps every file with the time it was written, which makes
# a restored .build think the whole package is newer than it and compile it all
# again: on GitHub that was twelve of the fifty three minutes a release spent in
# its test step (v0.19.0, 2026-10-26). The compiler decides what to rebuild by
# comparing each source's time with the one it recorded, so a time taken from
# the file's git blob is the same in every checkout where the file is the same,
# and different the moment the file changes.
#
# Run it right after checkout, before anything builds, in every job that
# restores or saves the build cache (.github/workflows/ci.yml, release.yml).
set -euo pipefail
cd "$(dirname "$0")/.."

# 2001-01-01 plus up to about eight and a half years, from the first seven hex
# digits of the blob. Never in the future, so nothing warns about clock skew.
git ls-files -s -z | perl -0 -ne '
  next unless /^\d+ ([0-9a-f]{40}) \d+\t(.+)\0?$/s;
  my ($sha, $path) = ($1, $2);
  $path =~ s/\0$//;
  next unless -f $path && ! -l $path;
  my $t = 978307200 + hex(substr($sha, 0, 7));
  utime($t, $t, $path) or warn "could not stamp $path\n";
  $n++;
  END { print "stamped $n files with times from their contents\n" }
'
