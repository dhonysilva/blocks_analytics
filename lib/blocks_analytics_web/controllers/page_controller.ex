defmodule BlocksAnalyticsWeb.PageController do
  use BlocksAnalyticsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
