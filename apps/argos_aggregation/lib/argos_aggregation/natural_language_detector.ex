defmodule ArgosAggregation.NaturalLanguageDetector do

  require Logger

  def get_language_key(string, threshold \\ 0.9)
  def get_language_key(string, threshold) when is_binary(string) do
    detection_result =
      try do
        string
        |> Tongue.detect()
        |> Enum.filter(fn ({_key, score}) ->
          score > threshold
        end)
        |> Enum.sort(fn ({_key, score}, :desc) ->
          score
        end)
        |> List.first()
      catch
        :exit, _value ->
          :retry
        end

    case detection_result do
      {lang_code, _score} ->
        Atom.to_string(lang_code)
      :retry ->
        Logger.warning("Detection process timed out, retrying to parse #{string}")
        get_language_key(string, threshold)
      nil ->
        # Nothing over threshold
        ""
    end
  end

  def get_language_key(_no_string, _) do
    #Logger.warning("Received a non-string!")
    ""
  end

  def get_language_keys_with_scores(string) when is_binary(string) do
    try do
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
    catch
      :exit, _value ->
        Logger.warning("Detection process timed out, retrying to parse #{string}")
        get_language_keys_with_scores(string)
      end
  end

  def get_language_keys_with_scores(_no_string) do
    Logger.warning("Received a non-string!")
    %{}
  end
end
