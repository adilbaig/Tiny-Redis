LIB = source/tinyredis/*.d source/tinyredis/collections/*.d
DEPS := $(LIB) Makefile

example: $(DEPS) examples/example.d
	rdmd -Isource examples/example.d

console: $(DEPS) examples/console.d
	rdmd -Isource examples/console.d

.PHONY: benchmark
benchmark: $(DEPS) benchmark/benchmark.d
	rdmd -Isource benchmark/benchmark.d

.PHONY: lib
lib: lib/libtinyredis.a

lib/libtinyredis.a: $(DEPS)
	mkdir -p lib
	dmd -Hdlib -o- $(LIB)
	dmd -lib $(LIB) -oflib/libtinyredis.a

.PHONY: test
test: $(DEPS)
	rdmd -debug=tinyredis --main -unittest -Isource source/tinyredis/parser.d
	rdmd -debug=tinyredis --main -unittest -Isource source/tinyredis/encoder.d
	rdmd -debug=tinyredis --main -unittest -Isource source/tinyredis/redis.d
	rdmd -debug=tinyredis --main -unittest -Isource source/tinyredis/collections/set.d
