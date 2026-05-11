defmodule FixtureApi do
  use CanOpener,
    spec: "test/support/openapi.json",
    otp_app: :can_opener,
    base_url: "https://api.fixture.test",
    auth: :bearer,
    path_prefix: "/api/v1/"
end

defmodule FixtureHeaderAuthApi do
  use CanOpener,
    spec: "test/support/openapi.json",
    otp_app: :can_opener,
    base_url: "https://api.fixture.test",
    auth: {:header, "X-API-Key"},
    path_prefix: "/api/v1/"
end

defmodule FixtureNoAuthApi do
  use CanOpener,
    spec: "test/support/openapi.json",
    otp_app: :can_opener,
    base_url: "https://api.fixture.test",
    auth: :none,
    path_prefix: "/api/v1/"
end
