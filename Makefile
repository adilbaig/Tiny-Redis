LIB = tinyredis/*.d
DEPS := $(LIB) Makefile

example: $(DEPS) examples/example.d
	rdmd examples/example.d $(LIB)

console: $(DEPS) examples/console.d
	rdmd examples/console.d $(LIB)

.PHONY: benchmark
benchmark: $(DEPS) benchmark/benchmark.d
	rdmd benchmark/benchmark.d $(LIB)

.PHONY: lib
lib: lib/libtinyredis.a

lib/libtinyredis.a: $(DEPS)
	mkdir -p lib
	dmd -Hdlib -o- $(LIB)
	dmd -lib $(LIB) -oflib/libtinyredis.a

.PHONY: test
test: $(DEPS) collections/set.d
	rdmd -debug=tinyredis --main -unittest tinyredis/parser.d
	rdmd -debug=tinyredis --main -unittest tinyredis/encoder.d
	rdmd -debug=tinyredis --main -unittest tinyredis/redis.d
	rdmd -debug=tinyredis --main -unittest collections/set.d
