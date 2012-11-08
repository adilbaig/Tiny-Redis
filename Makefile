LIB = tinyredis/*

example:
	rdmd src/example.d $(LIB)
	
console:
	rdmd src/console.d $(LIB)
	
benchmark:
	rdmd src/benchmark.d $(LIB)
	
lib:
	dmd -lib tinyredis/* -oftinyredis.a
	
release:
	dmd -lib -m32 tinyredis/* -oflibs/tinyredis_$(VERSION).a
	dmd -lib tinyredis/* -oflibs/tinyredis_$(VERSION)_x64.a
	rm -f TinyRedis.tgz
	tar czf TinyRedis.tgz src/* tinyredis/* libs/* README.md LICENSE
	
test:
	rdmd -debug --main -unittest tinyredis/parser.d
	rdmd -debug --main -unittest tinyredis/redis.d