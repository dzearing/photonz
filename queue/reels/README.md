# Reels

Every reel made for the user to watch: sizzle reels, transition and title reels,
before and after comparisons. Newest first in `reels.json`; shown on the
dashboard's Reels page (http://127.0.0.1:8791/#reels) and in Finder at
`~/Movies/Photonz Reels`.

Add one with `node queue/bin/reel-add.mjs <video.mp4> --title "..." --task <id>
--made-on "<version and app>" --kind sample|before|after|reference --notes "..."`.
Never copy a file in by hand: the list is what the page reads.
