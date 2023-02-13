dev:
	elixir --name gateway@127.0.0.1 --no-halt --cookie dev -S mix
start:
	mix run --no-halt
build:
	mix release
deps:
	mix deps.get
watch:
	reflex -R '^.elixir_ls' -R '^_build' -R 'deps' -r '\.*$\' make recompile
recompile:
	iex --name recompile@127.0.0.1 --cookie dev --remsh gateway --rpc-eval gateway 'IEx.Helpers.recompile()' -e ':erlang.halt'