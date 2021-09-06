defmodule ArgosCore.NaturalLanguageDetector do

  require Logger
  require Tongue

  def get_language_key(string, threshold \\ 0.9)
  def get_language_key(string, threshold) when is_binary(string) do
      detection_result =
        string
        |> Tongue.detect()
        |> Enum.filter(fn ({_key, score}) ->
          score > threshold
        end)
        |> Enum.sort(fn ({_key, score}, :desc) ->
          score
        end)
        |> List.first()

      case detection_result do
        {lang_code, _score} ->
          Atom.to_string(lang_code)
        nil ->
          # Nothing over threshold
          ""
      end
  end

  def get_language_key(no_string, _) do
    Logger.warning("Received a non-string while determining language key:")
    Logger.warning(no_string)
    ""
  end

  def get_language_keys_with_scores(string) when is_binary(string) do
    string
    |> Tongue.detect()
    |> Enum.sort(fn ({_key, value}, :desc) ->
      value
    end)
    |> Enum.map(fn({key, score}) ->
      %{
        lang: Atom.to_string(key),
        score: score
      }
    end)
  end

  def get_language_keys_with_scores(no_string) do
    Logger.warning("Received a non-string while determining scored language keys:")
    Logger.warning(no_string)
    %{}
  end
end
