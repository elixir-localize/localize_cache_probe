# Credo configuration for the Localize cache probe.
#
# Mirrors the Localize policy: strict, with `Design.AliasUsage` disabled
# and every other check left at its default.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
