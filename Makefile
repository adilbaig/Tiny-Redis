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
	dmd -lib -m32 tinyredis/* -oflibs/$(VERSION)/libtinyredis.a
	dmd -lib tinyredis/* -oflibs/$(VERSION)/libtinyredis_x64.a
	rm -f TinyRedis_$(VERSION).tgz
	tar czf TinyRedis_$(VERSION).tgz src/* tinyredis/* libs/$(VERSION)/* README.md LICENSE
	
test:
	rdmd -debug --main -unittest tinyredis/parser.d
	rdmd -debug --main -unittest tinyredis/redis.d