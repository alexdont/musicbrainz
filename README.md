# MusicBrainz

A [MusicBrainz](https://musicbrainz.org) client for the music of films and
shows: the soundtrack albums named after a title, and their tracks. No key, no
playback — each track can become a YouTube search link.

```elixir
def deps do
  [{:musicbrainz, "~> 0.1"}]
end
```

```elixir
{:ok, albums} = MusicBrainz.albums("Heat", year: 1995)
#=> [%{id: "…", title: "Heat (Music From the Motion Picture)", year: 1995, artist: "Various Artists"},
#    %{id: "…", title: "Heat: The Score", year: 1996, artist: "Elliot Goldenthal"}]

{:ok, tracks} = MusicBrainz.tracks(hd(albums).id)
#=> [%{n: 1, title: "Heat", artist: "Elliot Goldenthal feat. Kronos Quartet", secs: 461}, …]

MusicBrainz.youtube(["Elliot Goldenthal", "Heat", "Heat"])
#=> "https://www.youtube.com/results?search_query=Elliot+Goldenthal+Heat"
```

## What it picks

MusicBrainz is searched for *release groups* of secondary type
**soundtrack** whose name begins with the title's words — a search also
matches on one word, and *Body Heat* is not *Heat*'s. A film's albums are
those first released within a year of it (`year:`); a show's span its
seasons, so leave the year out. Oldest first: the original album before its
expanded editions, a show's seasons in order. Other names to try when the
first finds nothing (the original title) go in `names:`.

An album's tracks are those of its fullest official release, numbered
through its discs. An artist credited only in kana is named by the Latin
sort name MusicBrainz keeps ("Kanno, Yoko" → "Yoko Kanno"), so a search
finds the song.

## Being a good client

MusicBrainz is free and asks two things: a user agent that names your
application with a way to reach you, and no more than one request a second.

```elixir
config :musicbrainz, user_agent: "MyApp/1.0 (https://example.com)"
```

Keep the second yourself: cache the answers (albums for a month, tracks for
a year — they do not change). A `503` comes back as `{:error, :rate_limited}`.

## Testing

Every request merges `req_options`, so point it at `Req.Test`:

```elixir
config :musicbrainz, req_options: [plug: {Req.Test, MusicBrainz}]
```

## License

MIT © Alexander Don
