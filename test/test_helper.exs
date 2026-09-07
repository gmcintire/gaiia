# Make ExUnit fail fast on hung tests rather than hanging the suite.
ExUnit.start()

# Belt-and-braces: ensure that *any* test that forgets to stub the HTTP
# transport fails immediately instead of attempting a real connection.
# `Gaiia.ReqStub.run/1` raises when no stub is installed for the process.
Application.put_env(:gaiia, :endpoint, "http://192.0.2.1:1/graphql")
Application.put_env(:gaiia, :req_options, Gaiia.ReqStub.options())
