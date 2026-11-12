defmodule MusicBrainz do
  @moduledoc """
  The music of a film or a show, from [MusicBrainz](https://musicbrainz.org):
  the soundtrack albums named after the title, and their tracks.

      {:ok, albums} = MusicBrainz.albums("Heat", year: 1995)
      #=> [%{id: "…", title: "Heat (Music From the Motion Picture)", year: 1995,
      #      artist: "Various Artists"}, %{title: "Heat: The Score", …}]

      {:ok, tracks} = MusicBrainz.tracks(hd(albums).id)
      #=> [%{n: 1, title: "Heat", artist: "Elliot Goldenthal feat. Kronos Quartet", secs: 461}, …]

      MusicBrainz.youtube([hd(tracks).artist, hd(tracks).title, "Heat"])
      #=> "https://www.youtube.com/results?search_query=Elliot+Goldenthal+feat.+Kronos+Quartet+Heat"

  MusicBrainz is asked for *release groups* of secondary type **soundtrack**
  whose name begins with the title's words (a search also matches on one
  word: *Body Heat* is not *Heat*'s), for a film within a year of its
  release (`:year`), oldest first — the original album before its expanded
  editions, a show's seasons in order. An album's tracks are those of its
  fullest official release, numbered through its discs; an artist credited
  only in kana is named by the Latin sort name ("Kanno, Yoko" → "Yoko
  Kanno"), so a search finds the song.

  ## Being a good client

  MusicBrainz is free and keyless, and asks two things: a **user agent that
  names your application** with a way to reach you, and **one request a
  second**. Set the first:

      config :musicbrainz, user_agent: "MyApp/1.0 (https://example.com)"

  and keep the second yourself: cache what comes back (albums for a month,
  tracks for a year — they do not change) and do not ask in a loop. Nothing
  here plays music and no YouTube key is needed: `youtube/1` is a search link.

  Every request merges `:req_options` (per call or `config :musicbrainz,
  :req_options`), so the client can be pointed at `Req.Test`.
  """

  @base_url "https://musicbrainz.org/ws/2"
  @default_agent "musicbrainz-elixir/0.1 (https://hex.pm/packages/musicbrainz)"

  @typedoc "A release group: `year` is its first release's, `artist` the credit as printed."
  @type album :: %{
          id: String.t(),
          title: String.t(),
          year: integer | nil,
          artist: String.t() | nil
        }

  @typedoc "A track of the album's fullest release, numbered through its discs; `secs` its length."
  @type track :: %{
          n: pos_integer,
          title: String.t(),
          artist: String.t() | nil,
          secs: integer | nil
        }

  @doc """
  The soundtrack albums named after `name`, best first: `{:ok, [album]}`
  (`{:ok, []}` when MusicBrainz lists none) or `{:error, reason}`.

  Options:

    * `:year` — the film's release year: only albums first released within
      a year of it. Leave it out for a show, whose albums span its seasons.
    * `:names` — other names to try when the first finds nothing (the
      original title, say); the first name with albums wins.
    * `:limit` — albums at most (default 8).
    * `:req_options` — merged into the request.
  """
  @spec albums(String.t(), keyword()) :: {:ok, [album]} | {:error, term()}
  def albums(name, opts \\ []) when is_binary(name) do
    names =
      Enum.uniq(for n <- [name | Keyword.get(opts, :names, [])], is_binary(n), n != "", do: n)

    limit = Keyword.get(opts, :limit, 8)

    Enum.reduce_while(names, {:ok, []}, fn n, acc ->
      case get(
             "/release-group/",
             [query: query(n, year: Keyword.get(opts, :year)), limit: 25],
             opts
           ) do
        {:ok, %{"release-groups" => groups}} ->
          case pick_albums(groups, n, limit) do
            [] -> {:cont, acc}
            albums -> {:halt, {:ok, albums}}
          end

        {:ok, _} ->
          {:cont, acc}

        error ->
          {:halt, if(acc == {:ok, []}, do: error, else: acc)}
      end
    end)
  end

  @doc """
  The Lucene query `albums/2` sends: the name as a release-group title,
  soundtracks only, and with `:year` a first release within a year of it.
  """
  @spec query(String.t(), keyword()) :: String.t()
  def query(name, opts \\ []) do
    base = ~s(releasegroup:"#{escape(name)}" AND secondarytype:musicbrainz)

    case Keyword.get(opts, :year) do
      y when is_integer(y) -> base <> " AND firstreleasedate:[#{y - 1} TO #{y + 1}]"
      <<_::binary-size(4)>> = y -> query(name, year: String.to_integer(y))
      _ -> base
    end
  end

  defp escape(s), do: Regex.replace(~r/(["\\])/, s, "\\\\\\1")

  @doc """
  The release groups of a search answer whose name begins with `name`'s
  words, as albums: albums and EPs with a search score of 50 or more, oldest
  first, `limit` at most.
  """
  @spec pick_albums(term(), String.t(), pos_integer) :: [album]
  def pick_albums(groups, name, limit \\ 8)

  def pick_albums(groups, name, limit) when is_list(groups) do
    want = words(name)

    groups
    |> Enum.filter(fn g ->
      is_binary(g["id"]) and is_binary(g["title"]) and (g["score"] || 0) >= 50 and
        g["primary-type"] in ["Album", "EP", nil] and
        List.starts_with?(words(g["title"]), want)
    end)
    |> Enum.sort_by(&{&1["first-release-date"] || "9999", -(&1["score"] || 0)})
    |> Enum.take(limit)
    |> Enum.map(fn g ->
      %{
        id: g["id"],
        title: g["title"],
        year: year_of(g["first-release-date"]),
        artist: credit(g["artist-credit"])
      }
    end)
  end

  def pick_albums(_, _, _), do: []

  # A name as it is compared: its words, lower case.
  defp words(s), do: s |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)

  @doc """
  The tracks of the album (a release-group id): those of its fullest
  official release, `:limit` at most (default 60). `{:ok, []}` for a group
  with no release listed.
  """
  @spec tracks(String.t(), keyword()) :: {:ok, [track]} | {:error, term()}
  def tracks(mbid, opts \\ []) when is_binary(mbid) do
    params = [
      "release-group": mbid,
      inc: "recordings+artist-credits",
      status: "official",
      limit: 5
    ]

    case get("/release/", params, opts) do
      {:ok, %{"releases" => releases}} ->
        {:ok, parse_tracks(releases, Keyword.get(opts, :limit, 60))}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  @doc "The tracks of the fullest of these releases, numbered through its discs."
  @spec parse_tracks(term(), pos_integer) :: [track]
  def parse_tracks(releases, limit \\ 60)

  def parse_tracks(releases, limit) when is_list(releases) do
    releases
    |> Enum.map(fn r ->
      for m <- r["media"] || [], t <- m["tracks"] || [], is_binary(t["title"]), do: t
    end)
    |> Enum.max_by(&length/1, fn -> [] end)
    |> Enum.take(limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {t, n} ->
      %{
        n: n,
        title: t["title"],
        artist: credit(t["artist-credit"] || get_in(t, ["recording", "artist-credit"])),
        secs: secs(t["length"] || get_in(t, ["recording", "length"]))
      }
    end)
  end

  def parse_tracks(_, _), do: []

  @doc "A YouTube search for these words (blanks dropped, a word said twice once)."
  @spec youtube([String.t() | nil]) :: String.t()
  def youtube(words) when is_list(words) do
    q =
      words
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq_by(&String.downcase/1)
      |> Enum.join(" ")

    "https://www.youtube.com/results?search_query=" <> URI.encode_www_form(q)
  end

  # ── credits ───────────────────────────────────────────────────────

  defp credit(credits) when is_list(credits) and credits != [] do
    credits
    |> Enum.map_join("", fn c -> credited(c) <> (c["joinphrase"] || "") end)
    # A Japanese credit joins its names with "、".
    |> String.replace("、", ", ")
    |> String.trim()
    |> blank()
  end

  defp credit(_), do: nil

  # The name as credited — in Latin letters when MusicBrainz has one (a Japanese artist's own
  # name is kept in kana; the sort name, "Kanno, Yoko", is the Latin one).
  defp credited(c) do
    name = c["name"] || get_in(c, ["artist", "name"]) || ""

    if Regex.match?(~r/[A-Za-z]/, name) do
      name
    else
      case get_in(c, ["artist", "sort-name"]) do
        sort when is_binary(sort) ->
          if Regex.match?(~r/[A-Za-z]/, sort), do: unsorted(sort), else: name

        _ ->
          name
      end
    end
  end

  # "Kanno, Yoko" → "Yoko Kanno"; "Seatbelts, The" → "The Seatbelts".
  defp unsorted(sort) do
    case String.split(sort, ", ", parts: 2) do
      [last, first] -> first <> " " <> last
      _ -> sort
    end
  end

  defp secs(ms) when is_integer(ms) and ms > 0, do: div(ms, 1000)
  defp secs(_), do: nil

  defp year_of(<<y::binary-size(4), _::binary>>) do
    case Integer.parse(y) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp year_of(_), do: nil

  defp blank(""), do: nil
  defp blank(v), do: v

  # ── HTTP ──────────────────────────────────────────────────────────

  defp get(path, params, opts) do
    req =
      Req.new(
        base_url: @base_url,
        retry: false,
        receive_timeout: 8_000,
        headers: [{"user-agent", user_agent()}, {"accept", "application/json"}]
      )
      |> Req.merge(req_options(opts))

    case Req.get(req, url: path, params: Keyword.put(params, :fmt, "json")) do
      {:ok, %{status: 200, body: %{} = body}} -> {:ok, body}
      {:ok, %{status: 503}} -> {:error, :rate_limited}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  defp user_agent, do: Application.get_env(:musicbrainz, :user_agent, @default_agent)

  defp req_options(opts),
    do: Keyword.get(opts, :req_options) || Application.get_env(:musicbrainz, :req_options, [])
end
