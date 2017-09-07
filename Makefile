default: test

test:
	dub test --debug=tinyredis

.PHONY: benchmark
benchmark:
	dub run --config=benchmark

console:
	dub run --config=console
	
example:
	dub run --config=example
	
lib:
	dub build --config=library
	
clean:
	dub clean