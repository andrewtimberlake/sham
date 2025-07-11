defmodule Sham.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    if Code.ensure_loaded?(Bandit) do
      Application.ensure_all_started(:bandit)
    end

    DynamicSupervisor.start_link(strategy: :one_for_one, name: Sham.Supervisor)
  end
end
