defmodule Blockchain.StateTest do
  alias MerklePatriciaTree.Trie
  alias Blockchain.{Account, Transaction}
  alias Blockchain.Interface.AccountInterface

  use EthCommonTest.Harness
  use ExUnit.Case, async: true

  @passing_tests_by_group %{
    stExample: [:add11],
    stCallCodes: [
      :callcall_00,
      :callcode_checkPC
    ]
  }

  test "Blockchain state tests" do
    for {test_group_name, test_group} <- @passing_tests_by_group do
      for {_test_name, test} <- passing_tests(test_group_name, test_group) do
        state = account_interface(test).state

        transaction =
          %Transaction{
            nonce: load_integer(test["transaction"]["nonce"]),
            gas_price: load_integer(test["transaction"]["gasPrice"]),
            gas_limit: load_integer(List.first(test["transaction"]["gasLimit"])),
            to: maybe_hex(test["transaction"]["to"]),
            value: load_integer(List.first(test["transaction"]["value"]))
          }
          |> Transaction.Signature.sign_transaction(maybe_hex(test["transaction"]["secretKey"]))

        {state, _, _} =
          Transaction.execute_transaction(state, transaction, %Block.Header{
            beneficiary: maybe_hex(test["env"]["currentCoinbase"])
          })

        assert state.root_hash == maybe_hex(List.first(test["post"]["Frontier"])["hash"])
      end
    end
  end

  def dump_state(state) do
    state
    |> Trie.Inspector.all_values()
    |> Enum.map(fn {key, value} ->
      k = Base.encode16(key, case: :lower)
      v = value |> ExRLP.decode() |> Account.deserialize()
      {k, v}
    end)
    |> Enum.map(fn {address_key, account} ->
      IO.puts(address_key)
      IO.puts("  Balance: #{account.balance}")
      IO.puts("  Nonce: #{account.nonce}")
      IO.puts("  Storage Root:")
      IO.puts("  " <> Base.encode16(account.storage_root))
      IO.puts("  Code Hash")
      IO.puts("  " <> Base.encode16(account.code_hash))
    end)
  end

  def passing_tests(test_group_name, test_group) do
    test_group
    |> Enum.filter(fn test_name ->
      test_group == :all || Enum.member?(test_group, test_name)
    end)
    |> Enum.map(fn test_name ->
      {test_name, read_state_test_file(test_group_name, test_name)}
    end)
  end

  def read_state_test_file(type, test_name) do
    {:ok, body} = File.read(state_test_file_name(type, test_name))
    Poison.decode!(body)[Atom.to_string(test_name)]
  end

  def state_test_file_name(type, test) do
    System.cwd() <>
      "/../../ethereum_common_tests/GeneralStateTests/#{Atom.to_string(type)}/#{test}.json"
  end

  def account_interface(test) do
    db = MerklePatriciaTree.Test.random_ets_db()

    state = %Trie{
      db: db,
      root_hash: maybe_hex(test["env"]["previousHash"])
    }

    state =
      Enum.reduce(test["pre"], state, fn {address, account}, state ->
        storage = %Trie{root_hash: Trie.empty_trie_root_hash()}

        storage =
          Enum.reduce(account["storage"], storage, fn {key, value}, trie ->
            Trie.update(trie, load_integer(key), load_integer(value))
          end)

        new_account = %Account{
          nonce: load_integer(account["nonce"]),
          balance: load_integer(account["balance"]),
          storage_root: storage.root_hash
        }

        state
        |> Account.put_account(maybe_hex(address), new_account)
        |> Account.put_code(maybe_hex(address), maybe_hex(account["code"]))
      end)

    AccountInterface.new(state)
  end
end
