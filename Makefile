LIB = tinyredis/*

example:
	rdmd examples/example.d $(LIB)
	
console:
	rdmd examples/console.d $(LIB)
	
benchmark:
	rdmd benchmark/benchmark.d $(LIB)
	
lib:
	dmd -lib tinyredis/* -oflibtinyredis.a
	
test:
	rdmd -debug --main -unittest tinyredis/parser.d
	rdmd -debug --main -unittest tinyredis/redis.d