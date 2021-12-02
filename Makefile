default: lib

test:
	dub test --debug=tinyredis

lib: test
	dub build --config=library --build=release

.PHONY: benchmark
benchmark:
	dub run --config=benchmark

console:
	dub run --config=console

example:
	dub run --config=example

clean:
	dub clean