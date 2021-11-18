defmodule ArgosAPITest do
  use ExUnit.Case, async: true
  use Plug.Test
  doctest ArgosAPI

  alias ArgosAPI.{
    TestHelpers
  }

  @example_json Application.app_dir(:argos_core, "priv/example_collection_params.json")

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

  test "invalid distance filter yields 400 status" do
    response =
      conn(:get, "/search?filter[]=distance:invalid")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?filter[]=distance:0,0,-5")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400
  end

  test "invalid bounding box filter yields 400 status" do
    response =
      conn(:get, "/search?filter[]=bounding_box:invalid")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400


    response =
      conn(:get, "/search?filter[]=bounding_box:a,b,c,d")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    # Top is below bottom corner (latitudes invalid: parameter 1 < parameter 3)
    response =
      conn(:get, "/search?filter[]=bounding_box:0,0,50,50")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    # Left is to the right corner (longitudes invalid: parameter 0 > parameter 2)
    response =
      conn(:get, "/search?filter[]=bounding_box:50,50,0,0")
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
      conn(:get, "/public/openapi.json")
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

  describe "elastic search interaction |" do

    setup do
      TestHelpers.create_index()
      with {:ok, file_content} <- File.read(@example_json) do
        {:ok,data} = Poison.decode(file_content)
        data
        |> ArgosCore.Collection.CollectionParser.parse_collection()
        |> case do
          {:ok, params} -> params
        end
        |> ArgosCore.ElasticSearch.Indexer.index()
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

      # 1 collection, 2 places, 1 temporal concept, 5 places linked to the temporal concept
      assert total == 9
    end

    test "urls provided by info controller resolve" do
      %{"swagger_spec" => spec_path, "swagger_ui" => ui_path} =
        conn(:get, "/")
        |> ArgosAPI.Router.call(%{})
        |> case do
          %{resp_body: body} ->
            body
          end
        |> Poison.decode!()

      {:ok, _} =
        ArgosCore.HTTPClient.get(spec_path)


      {:ok, _} =
        ArgosCore.HTTPClient.get(ui_path)
    end

    test "document is accessable through endpoint" do
      %{resp_body: body } =
        conn(:get, "/doc/collection_1")
        |> ArgosAPI.Router.call(%{})

      assert %{"core_fields" => %{"id" => "collection_1" }} = Poison.decode!(body)
    end

    test "invalid document id yields 404" do
      %{status: status } =
        conn(:get, "/doc/non_existing")
        |> ArgosAPI.Router.call(%{})

      assert status == 404
    end

    test "valid distance filter yields 200 status" do
      response =
        conn(:get, "/search?filter[]=distance:13.30039,52.4599,5")
        |> ArgosAPI.Router.call(%{})

      assert response.status == 200
    end

    test "valid bounding box filter yields 200 status" do
      response =
        conn(:get, "/search?filter[]=bounding_box:0,50,50,0")
        |> ArgosAPI.Router.call(%{})

      assert response.status == 200
    end
  end
end
