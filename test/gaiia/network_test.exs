defmodule Gaiia.NetworkTest do
  @moduledoc """
  Explicit verification of the Network-domain operations. Schema only
  exposes three at this time:

    * `Gaiia.Queries.network_site/3`
    * `Gaiia.Queries.accounts_in_network_sites/3`
    * `Gaiia.Mutations.add_impacted_accounts_to_incident_from_network_sites/3`
  """

  use ExUnit.Case, async: true

  alias Gaiia.Client
  alias Gaiia.ReqStub

  @endpoint "http://192.0.2.1:1/graphql"

  defp capturing_client do
    Client.new(endpoint: @endpoint, req_options: ReqStub.install_ok())
  end

  describe "network queries" do
    test "network_site/3 builds a networkSite($id: GlobalID!) query" do
      client = capturing_client()

      assert {:ok, _} = Gaiia.Queries.network_site(client, %{"id" => "network_site_abc"}, "id name")

      body = ReqStub.captured_body()
      assert body["query"] == "query networkSite($id: GlobalID!) { networkSite(id: $id) { id name } }"
      assert body["variables"] == %{"id" => "network_site_abc"}
    end

    test "accounts_in_network_sites/3 includes the required filters arg" do
      client = capturing_client()

      vars = %{"filters" => %{"networkSiteIds" => ["network_site_abc"]}, "first" => 25}

      assert {:ok, _} =
               Gaiia.Queries.accounts_in_network_sites(
                 client,
                 vars,
                 "edges { node { id name } } pageInfo { hasNextPage endCursor }"
               )

      body = ReqStub.captured_body()
      assert body["query"] =~ "$filters: AccountsInNetworkSitesQueryFilters!"
      assert body["query"] =~ "$first: Int"
      assert body["query"] =~ "accountsInNetworkSites(filters: $filters, first: $first)"
      assert body["variables"] == vars
    end

    test "accounts_in_network_sites/3 declares only the supplied optional args" do
      client = capturing_client()

      Gaiia.Queries.accounts_in_network_sites(
        client,
        %{"filters" => %{}, "after" => "cursor1"},
        "edges { node { id } }"
      )

      body = ReqStub.captured_body()
      assert body["query"] =~ "$after: String"
      refute body["query"] =~ "$first"
      refute body["query"] =~ "$last"
      refute body["query"] =~ "$before"
    end
  end

  describe "network mutations" do
    test "add_impacted_accounts_to_incident_from_network_sites/3 builds the mutation" do
      client = capturing_client()

      input = %{
        "incidentId" => "incident_abc",
        "networkSiteIds" => ["network_site_1", "network_site_2"]
      }

      assert {:ok, _} =
               Gaiia.Mutations.add_impacted_accounts_to_incident_from_network_sites(
                 client,
                 %{"input" => input},
                 "incident { id impactedAccountsCount }"
               )

      body = ReqStub.captured_body()
      assert body["query"] =~ "mutation addImpactedAccountsToIncidentFromNetworkSites"
      assert body["query"] =~ "$input: AddImpactedAccountsToIncidentFromNetworkSitesInput!"
      assert body["query"] =~ "addImpactedAccountsToIncidentFromNetworkSites(input: $input)"
      assert body["variables"] == %{"input" => input}
    end
  end
end
