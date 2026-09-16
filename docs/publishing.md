# Publishing and video credits

The new animated “Housefly” is CC BY 4.0. The public packages retain
`THIRD_PARTY_NOTICES.md`; do not upload the separate restricted fly backup
from outside this project. The fly, MaleCNS data, and apartment all require
CC BY 4.0 attribution. The swatter model also requires attribution.

## Copy into a game page or video description

> Apartment art: “Modern Apartment” by Visthétique —
> https://sketchfab.com/3d-models/modern-apartment-1fbb649cd6624f2bb7b7d6e30c6533a5 —
> CC BY 4.0: https://creativecommons.org/licenses/by/4.0/ . Adapted for
> Escape Circuit with Godot lighting, simplified collisions, fly perches,
> camera placement, and a bedroom doorway.
>
> Connectome data: MaleCNS v1.0 by the MaleCNS collaboration —
> https://male-cns.janelia.org/download/ — CC BY 4.0. The game extracts a
> selected escape-circuit connection summary; its stimulus encoding and
> movement are engineered, not a validated biological fly simulation.
>
> Fly art: “Housefly” by schmoldt.art —
> https://sketchfab.com/3d-models/housefly-5fe7cbd25f9a446d8bae005893d010dd —
> CC BY 4.0: https://creativecommons.org/licenses/by/4.0/ . Adapted for
> Escape Circuit: display pedestal omitted, body reoriented, and wing
> geometry separated and animated during flight and replay.
>
> Swatter art: “Fly Swatter” by reconpeanut —
> https://sketchfab.com/3d-models/fly-swatter-1cbb42b179424bcc8d051e7363e3829d —
> CC BY 4.0: https://creativecommons.org/licenses/by/4.0/ . Scaled and
> reoriented for the first-person view; gameplay hit area unchanged.

## Release steps

1. Play-test the current Windows export and review the screen-recorded V-key
   split-screen replay. T toggles the telemetry during normal play.
2. On itch.io, create an **HTML Game** and upload
   `dist/Escape-Circuit-web.zip`. The build script now verifies itch.io's
   extracted-file and single-file limits. Preview the page before publishing;
   the browser build still needs a real-browser performance check.
3. Upload `dist/Escape-Circuit-windows-x86_64.zip` as a Windows download.
   Keep `THIRD_PARTY_NOTICES.md` bundled with it.
4. Add the credits above to the game page and the YouTube description. Do not
   describe the fly as a whole-brain or biologically validated simulation.
5. Commit the source to Git and publish a repository only after reviewing the
   file list; `data/connectome/`, local build caches, and the restricted backup
   should stay outside the public repository.

The browser release is large because of the detailed apartment. Meeting host
limits does not establish good loading time or performance on other computers.
