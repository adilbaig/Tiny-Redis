LIB = tinyredis/*

example:
	rdmd src/example.d $(LIB)
	
console:
	rdmd src/console.d $(LIB)
	
test:
	rdmd -debug --main -unittest tinyredis/parser.d
	rdmd -debug --main -unittest tinyredis/redis.d