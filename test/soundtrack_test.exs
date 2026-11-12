defmodule SoundtrackTest do
  use ExUnit.Case, async: false

  setup do
    Application.put_env(:soundtrack, :req_options, plug: {Req.Test, Soundtrack})
    on_exit(fn -> Application.delete_env(:soundtrack, :req_options) end)
    :ok
  end

  test "a film is searched within a year of its release, a show by name alone" do
    assert Soundtrack.query("Heat", year: 1995) ==
             ~s(releasegroup:"Heat" AND secondarytype:soundtrack AND firstreleasedate:[1994 TO 1996])

    assert Soundtrack.query("Heat", year: "1995") =~ "[1994 TO 1996]"

    assert Soundtrack.query("Game of Thrones") ==
             ~s(releasegroup:"Game of Thrones" AND secondarytype:soundtrack)

    # Quotes in a name are escaped, not ended.
    assert Soundtrack.query(~s(The "Movie")) =~ ~s(releasegroup:"The \\"Movie\\"")
  end

  test "the albums kept are the ones named after the title, oldest first, a handful at most" do
    groups =
      [
        %{
          "id" => "a",
          "title" => "Heat (Music From the Motion Picture)",
          "score" => 100,
          "primary-type" => "Album",
          "first-release-date" => "1995-12-19",
          "artist-credit" => [%{"name" => "Various Artists"}]
        },
        # A search matches on words: this is not the film's.
        %{"id" => "b", "title" => "Body Heat", "score" => 90, "primary-type" => "Album"},
        %{"id" => "c", "title" => "Heat", "score" => 40, "primary-type" => "Album"},
        %{
          "id" => "d",
          "title" => "Heat: The Score",
          "score" => 80,
          "primary-type" => "Album",
          "first-release-date" => "1996"
        },
        %{"id" => "e", "title" => "Heat", "score" => 80, "primary-type" => "Single"}
      ] ++
        for(
          n <- 1..6,
          do: %{"id" => "x#{n}", "title" => "Heat #{n}", "score" => 60, "primary-type" => "Album"}
        )

    albums = Soundtrack.pick_albums(groups, "Heat")
    assert Enum.map(albums, & &1.id) == ["a", "d", "x1", "x2", "x3", "x4", "x5", "x6"]

    assert hd(albums) == %{
             id: "a",
             title: "Heat (Music From the Motion Picture)",
             year: 1995,
             artist: "Various Artists"
           }

    assert length(Soundtrack.pick_albums(groups, "Heat", 2)) == 2
    assert Soundtrack.pick_albums(nil, "Heat") == []
  end

  test "the tracks are the fullest release's, numbered through its discs, with the artist and length" do
    releases = [
      %{"media" => [%{"tracks" => [%{"title" => "Only one", "length" => 1000}]}]},
      %{
        "media" => [
          %{
            "tracks" => [
              %{
                "title" => "Heat",
                "length" => 461_826,
                "artist-credit" => [
                  %{"name" => "Elliot Goldenthal", "joinphrase" => " feat. "},
                  %{"name" => "Kronos Quartet"}
                ]
              }
            ]
          },
          %{
            "tracks" => [
              %{
                "title" => "Condensers",
                "recording" => %{
                  "length" => 155_000,
                  "artist-credit" => [%{"artist" => %{"name" => "Elliot Goldenthal"}}]
                }
              }
            ]
          }
        ]
      }
    ]

    assert Soundtrack.parse_tracks(releases) == [
             %{n: 1, title: "Heat", artist: "Elliot Goldenthal feat. Kronos Quartet", secs: 461},
             %{n: 2, title: "Condensers", artist: "Elliot Goldenthal", secs: 155}
           ]

    assert [%{n: 1}] = Soundtrack.parse_tracks(releases, 1)
    assert Soundtrack.parse_tracks([]) == []
  end

  test "an artist credited in kana is named by the Latin sort name, first name first" do
    releases = [
      %{
        "media" => [
          %{
            "tracks" => [
              %{
                "title" => "Tank!",
                "artist-credit" => [
                  %{
                    "name" => "シートベルツ",
                    "artist" => %{"name" => "シートベルツ", "sort-name" => "Seatbelts, The"}
                  }
                ]
              },
              %{
                "title" => "Rush",
                "artist-credit" => [
                  %{
                    "name" => "菅野よう子",
                    "artist" => %{"sort-name" => "Kanno, Yoko"},
                    "joinphrase" => " & "
                  },
                  %{"name" => "シートベルツ", "artist" => %{"sort-name" => "シートベルツ"}}
                ]
              }
            ]
          }
        ]
      }
    ]

    assert [%{artist: "The Seatbelts"}, %{artist: "Yoko Kanno & シートベルツ"}] =
             Soundtrack.parse_tracks(releases)
  end

  test "a YouTube search carries the words that are there, each once" do
    assert Soundtrack.youtube(["Hans Zimmer", nil, "Dust", "", "Interstellar"]) ==
             "https://www.youtube.com/results?search_query=Hans+Zimmer+Dust+Interstellar"

    assert Soundtrack.youtube(["Kronos Quartet", "Heat", "Heat"]) ==
             "https://www.youtube.com/results?search_query=Kronos+Quartet+Heat"
  end

  test "albums/2 asks MusicBrainz with the user agent, tries the other names, and tracks/2 reads a group" do
    Application.put_env(:soundtrack, :user_agent, "test/1 (x)")
    on_exit(fn -> Application.delete_env(:soundtrack, :user_agent) end)

    Req.Test.stub(Soundtrack, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert Plug.Conn.get_req_header(conn, "user-agent") == ["test/1 (x)"]
      assert conn.query_params["fmt"] == "json"

      case {conn.request_path, conn.query_params} do
        {"/ws/2/release-group/", %{"query" => "releasegroup:\"Nothing\"" <> _}} ->
          Req.Test.json(conn, %{"release-groups" => []})

        {"/ws/2/release-group/", %{"query" => q}} ->
          assert q =~ ~s(releasegroup:"Heat")
          assert q =~ "[1994 TO 1996]"

          Req.Test.json(conn, %{
            "release-groups" => [
              %{"id" => "g1", "title" => "Heat", "score" => 100, "primary-type" => "Album"}
            ]
          })

        {"/ws/2/release/", %{"release-group" => "g1"}} ->
          Req.Test.json(conn, %{
            "releases" => [
              %{"media" => [%{"tracks" => [%{"title" => "Heat", "length" => 2000}]}]}
            ]
          })
      end
    end)

    assert {:ok, [%{id: "g1", title: "Heat"}]} =
             Soundtrack.albums("Nothing", names: ["Heat"], year: 1995)

    assert {:ok, [%{n: 1, title: "Heat", secs: 2}]} = Soundtrack.tracks("g1")
  end

  test "errors are values" do
    Req.Test.stub(Soundtrack, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)
    assert Soundtrack.albums("Heat") == {:error, :rate_limited}
    assert Soundtrack.tracks("g1") == {:error, :rate_limited}
  end
end
