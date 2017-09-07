default: test

test:
	dub test --debug=tinyredis

.PHONY:
benchmark:
	dub run --config=benchmark

console:
	dub build --config=console
	
example:
	dub run --config=example
	
lib:
	dub build --config=library
	
clean:
	dub clean