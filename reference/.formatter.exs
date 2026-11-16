# Used by "mix format"
#
# The macros of Plug are listed here, not imported with `import_deps`:
# the pre-commit hook formats these files from the repository root,
# where Plug is not a dependency.
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [plug: 1, plug: 2, get: 2, match: 2]
]
