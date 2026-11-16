import Config

# The locales the origin serves. `fr-CA` and `fr-CH` are there so that
# the probe's region scenario has two regions of one language to ask for.
config :localize,
  supported_locales: ~w(en fr de fr-CA fr-CH),
  default_locale: "en"

config :logger, level: :warning
