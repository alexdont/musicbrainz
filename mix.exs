defmodule Soundtrack.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "The soundtrack albums of a film or show from MusicBrainz, with their tracks: release groups of type soundtrack named after the title, within a year of a film's release, artists in Latin letters — and a YouTube search link per track. No key, no playback."
  @source_url "https://github.com/alexdont/soundtrack"

  def project do
    [
      app: :soundtrack,
      version: @version,
      description: @description,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:req, "~> 0.4 or ~> 0.5 or ~> 0.6"},
      {:plug, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "soundtrack",
      maintainers: ["Alexander Don"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "MusicBrainz API" => "https://musicbrainz.org/doc/MusicBrainz_API"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      name: "Soundtrack",
      source_ref: "v#{@version}",
      source_url: @source_url,
      main: "Soundtrack",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
