defmodule ArgosAPITest do
  use ExUnit.Case, async: true
  use Plug.Test
  doctest ArgosAPI

  alias ArgosAPI.{
    TestHelpers
  }

  @example_json "../../priv/example_projects_params.json"

  test "invalid size yields 400 status" do
    response =
      conn(:get, "/search", %{size: "invalid"})
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?size=-1")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?size=10.5")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400
  end

  test "invalid from yields 400 status" do
    response =
      conn(:get, "/search?from=invalid")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?from=-1")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?from=10.5")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400
  end

  test "invalid filters yield 400 status" do
    %{status: status} =
      conn(:get, "/search?filter[]=missing_colon")
      |> ArgosAPI.Router.call(%{})

    assert status == 400

    %{status: status} =
      conn(:get, "/search?!filter[]=missing_colon")
      |> ArgosAPI.Router.call(%{})

    assert status == 400

    %{status: status} =
      conn(:get, "/search?filter=missing_brackets")
      |> ArgosAPI.Router.call(%{})

    assert status == 400

  end

  test "swagger spec is served" do
    %{resp_body: body} = response =
      conn(:get, "/swagger/openapi.json")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 200

    %{"info" => %{"version" => version }} =
      body
      |> Poison.decode!()

    assert version == List.to_string(Application.spec(:argos_api, :vsn))
  end

  test "swagger ui is served" do
    response =
      conn(:get, "/swagger")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 200
  end

  describe "elastic search tests" do

    setup do
      TestHelpers.create_index()
      with {:ok, file_content} <- File.read(@example_json) do
        {:ok,data} = Poison.decode(file_content)
        data
        |> ArgosAggregation.Project.ProjectParser.parse_project()
        |> case do
          {:ok, params} -> params
        end
        |> ArgosAggregation.ElasticSearch.Indexer.index()
      end
      TestHelpers.refresh_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "basic search yields result" do
      %{resp_body: body } =
        conn(:get, "/search?q=*")
        |> ArgosAPI.Router.call(%{})

      %{"total" => total} =
        body
        |> Poison.decode!()

      # 1 project, 2 places, 1 concept
      assert total == 4
    end

    test "document is accessable through endpoint" do
      %{resp_body: body } =
        conn(:get, "/doc/project_1")
        |> ArgosAPI.Router.call(%{})

      assert %{"core_fields" => %{"id" => "project_1" }} = Poison.decode!(body)
    end

    test "invalid document id yields 404" do
      %{status: status } =
        conn(:get, "/doc/non_existing")
        |> ArgosAPI.Router.call(%{})

      assert status == 404
    end
  end
end
