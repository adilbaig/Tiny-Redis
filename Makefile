LIB = tinyredis/*

example:
	rdmd examples/example.d $(LIB)
	
console:
	rdmd examples/console.d $(LIB)
	
benchmark:
	rdmd benchmark/benchmark.d $(LIB)
	
lib:
	mkdir lib
	dmd -Hdlib -o- tinyredis/*
	dmd -lib tinyredis/* -oflib/libtinyredis.a
	
test:
	rdmd -debug=tinyredis --main -unittest tinyredis/parser.d
	rdmd -debug=tinyredis --main -unittest tinyredis/encoder.d
	rdmd -debug=tinyredis --main -unittest tinyredis/redis.d
	rdmd -debug=tinyredis --main -unittest collections/set.d
