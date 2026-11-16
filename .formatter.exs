# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],

  # The reference origin is a project of its own with rules of its own,
  # and the pre-commit hook formats its files from this directory.
  subdirectories: ["reference"]
]
