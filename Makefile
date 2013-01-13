LIB = tinyredis/*
VERSION=1.2.1

example:
	rdmd src/example.d $(LIB)
	
console:
	rdmd src/console.d $(LIB)
	
benchmark:
	rdmd src/benchmark.d $(LIB)
	
lib:
	dmd -lib tinyredis/* -oflibtinyredis.a
	
release:
	dmd -lib -m32 tinyredis/* -ofdownloads/$(VERSION)/libtinyredis.a
	dmd -lib tinyredis/* -ofdownloads/$(VERSION)/libtinyredis_x64.a
	rm -f downloads/$(VERSION)/TinyRedis_$(VERSION).tgz
	tar czf downloads/$(VERSION)/TinyRedis_$(VERSION).tgz src/* tinyredis/* README.md LICENSE changelog.md Makefile
	
test:
	rdmd -debug --main -unittest tinyredis/parser.d
	rdmd -debug --main -unittest tinyredis/redis.d