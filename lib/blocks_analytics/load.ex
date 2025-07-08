defmodule BlocksAnalytics.Load do
  use Agent

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> [] end, name: name)
  end

  @doc """
  Adds new block and returns oldest block (if any),
  to be removed from the page
  """
  def add_block(pid \\ __MODULE__, block) do
    Agent.get_and_update(pid, fn state ->
      new_state = [block | state]

      if length(new_state) > 10 do
        [last_block] = Enum.take(new_state, -1)
        {last_block, Enum.drop(new_state, -1)}
      else
        {nil, new_state}
      end
    end)
  end

  @doc """
  Returns a list with all currently stored blocks
  """
  def get_all_blocks(pid \\ __MODULE__) do
    Agent.get(pid, & &1)
  end
end
