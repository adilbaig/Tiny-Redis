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
	dmd -lib -m32 tinyredis/* -oflibs/tinyredis.a
	dmd -lib tinyredis/* -oflibs/tinyredis_x64.a
	rm TinyRedis.tgz
	tar czf TinyRedis.tgz ../Tiny-Redis/*
	
test:
	rdmd -debug --main -unittest tinyredis/parser.d
	rdmd -debug --main -unittest tinyredis/redis.d