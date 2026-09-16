# Third-party notices

## Godot Engine

Escape Circuit is built with the Godot Engine, distributed under the MIT License. Godot is not bundled in the source repository.

Source: https://github.com/godotengine/godot

## MaleCNS v1.0

The optional MaleCNS v1.0 dataset maps the adult male *Drosophila melanogaster* brain and ventral nerve cord. It is provided by the MaleCNS collaboration under CC BY 4.0 and is downloaded separately from the official release location.

Source and attribution guidance: https://male-cns.janelia.org/download/

Selected runtime connectivity is derived from MaleCNS v1.0 under the same CC BY 4.0 attribution requirement. The generated artifact records the source release, source-page URL, and SHA-256 digests of the exact annotation and connectivity inputs.

Please cite: Berg, S. et al. “Sexual dimorphism in the complete Drosophila male central nervous system connectome.” *Cell* 189(18), 5504–5526.e15 (2026). https://doi.org/10.1016/j.cell.2026.08.015

Official supplemental repository: https://github.com/flyconnectome/2025malecns

Additional scientific references are recorded in `brain/circuits/malecns-v1.0-looming-escape.json` and `docs/neuroscience.md`.

## External implementation references

The project documentation refers to public connectome projects for comparison and provenance. Reference does not imply that their source code has been copied into this repository. No third-party implementation source is included.

## Fly model

“Housefly” by [schmoldt.art](https://sketchfab.com/schmoldt.art) is included under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). Original model: [Sketchfab listing](https://sketchfab.com/3d-models/housefly-5fe7cbd25f9a446d8bae005893d010dd). The supplied `housefly.zip` contains its original `license.txt`, glTF geometry, and textures at `assets/models/fly_housefly_ccby/`.

The game omits the model's display pedestal, scales and reorients the fly, separates its original transparent wing geometry into two pivots, and animates the wings during flight and replay. Credit the author and link the model and license in any public game page, repository, or video description, and indicate these changes. The earlier Personal Use License fly and CC0 scan are not part of the runtime model.

## Modern Apartment

“Modern Apartment” by [Visthétique](https://sketchfab.com/visthetique) is included under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). Original model: [Sketchfab listing](https://sketchfab.com/3d-models/modern-apartment-1fbb649cd6624f2bb7b7d6e30c6533a5). The supplied archive contains its original `license.txt`, glTF geometry, and textures at `assets/models/apartment/modern_apartment/`.

The game adapts the model with Godot lighting, simplified gameplay collisions, fly perches, camera placement, and an open bedroom doorway. Credit the author and link the model and license in any public game page, repository, or video description. Indicate that these gameplay changes were made.
