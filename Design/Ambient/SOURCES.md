# Ambient panel — sources des ressources

Chaque tuile du panneau des ambiances (`AmbientSound`) attend :

- une image `ambient-<id>` dans `whoa-notch/Resources/Assets.xcassets` (carré, ~256 px, JPEG) ;
- une boucle `ambient-<id>.m4a` dans `whoa-notch/Resources/Ambient/` (60–120 s, raccord sans coupure,
  niveau sonore comparable entre les six).

Remplir une ligne par fichier dès qu'il est ajouté : source, auteur, licence, date de récupération.

| id | Image (source · auteur · licence) | Boucle (source · auteur · licence) |
|---|---|---|
| cozy | [Fireplace with a pile of firewood](https://unsplash.com/photos/pile-of-fire-woods-beside-fireplace-kNv_RMzdxJQ) · Lucian Alexe · Unsplash License · 2026-11-14 | [Fireplace Sound loop](https://opengameart.org/content/fireplace-sound-loop) · PagDev · CC0 (per listing) · 2026-11-14 |
| rain | [Rain drops on a window with a city behind](https://unsplash.com/photos/rain-drops-on-a-window-with-a-city-in-the-background-20vHjfKOopw) · Toushif Alam · Unsplash License · 2026-11-14 | [AMB Rain Loop 2](https://opengameart.org/content/amb-rain-loop-2) · Kresiek The Furry · CC0 (per listing) · 90 s cut from the 12-min file, ends crossfaded into the start · 2026-11-14 |
| study | [Desk lamp beside a pile of books](https://unsplash.com/photos/turned-on-desk-lamp-beside-pile-of-books-8muUTAmcWU4) · Jez Timms · Unsplash License · 2026-11-14 | [Ambient Relaxing Loop](https://opengameart.org/content/ambient-relaxing-loop) · isaiah658 · CC0 (per listing) · 2026-11-14 |
| jazz | [Close-up of piano keys, black and white](https://unsplash.com/photos/close-up-of-piano-keys-in-black-and-white-ONrsj0OpkVg) · Juan Pablo · Unsplash License · 2026-11-14 | |
| lofi | [Misty mountain peaks at sunrise](https://unsplash.com/photos/misty-mountain-peaks-at-sunrise-with-soft-pastel-sky-A1IoRfRQHuk) · Marek Piwnicki · Unsplash License · 2026-11-14 | |

Licences acceptées : Unsplash License, Pixabay Content License, CC0. CC-BY demande un crédit
(à ajouter dans la section Credits du README). Pas de CC-BY-NC ni de Unsplash+.

Images are 512 × 512 JPEG crops (shown at 256 pt @2x), requested from the Unsplash CDN at `w=512&h=512&fit=crop`.
All six images are in. Audio: cozy, rain and study are in; jazz and lo-fi are still to add.
Audio prep: decoded, trimmed or crossfaded into a loop, levelled to a common RMS and written as 128 kbps AAC (m4a). The Downloads originals are untouched.
