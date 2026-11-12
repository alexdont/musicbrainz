# Changelog

## 0.1.0

Initial release.

- `albums/2` — the soundtrack release groups named after a title, a film's
  within a year of its release, oldest first; `query/2`, `pick_albums/3`.
- `tracks/2` — an album's tracks from its fullest official release, artists
  in Latin letters; `parse_tracks/2`.
- `youtube/1` — a search link for a track.
- A configurable user agent (MusicBrainz asks for one); errors as values; a
  `req_options` seam for `Req.Test`.
