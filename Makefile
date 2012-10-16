LIB = tinyredis/*

example:
	rdmd src/example.d $(LIB)
	
console:
	rdmd src/console.d $(LIB)
	
benchmark:
	rdmd src/benchmark.d $(LIB)
	
lib:
	dmd -lib -m32 tinyredis/* -oftinyredis.a
	
test:
	rdmd -debug --main -unittest tinyredis/parser.d
	rdmd -debug --main -unittest tinyredis/redis.d