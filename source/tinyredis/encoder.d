module tinyredis.encoder;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

import std.array : Appender, appender;
import std.conv : to, text;
import std.string : format;
import std.traits : isSomeChar, isSomeString, isArray;

alias encode = toMultiBulk;

/**
 Take an array of (w|d)string arguments and concat them to a single Multibulk

 Examples:

 ---
 toMultiBulk("SADD", ["fruits", "apple", "banana"]) == toMultiBulk("SADD fruits apple banana")
 ---
 */

@trusted auto toMultiBulk(C, T)(const C[] command, T[][] args) if (isSomeChar!C && isSomeChar!T)
{
	auto buffer = appender!(C[])();
	buffer.reserve(command.length + args.length * 70); //guesstimate

	buffer ~= "*" ~ to!(C[])(args.length + 1) ~ "\r\n" ~ toBulk(command);

	foreach (c; args) {
		buffer ~= toBulk(c);
	}

	return buffer[];
}

/**
 Take an array of varargs and concat them to a single Multibulk

 Examples:

 ---
 toMultiBulk("SADD", "random", 1, 1.5, 'c') == toMultiBulk("SADD random 1 1.5 c")
 ---
 */
@trusted auto toMultiBulk(C, T...)(const C[] command, T args) if (isSomeChar!C)
{
	auto buffer = appender!(C[])();
	auto l = accumulator!(C,T)(buffer, args);
	return "*" ~ to!(C[])(l + 1) ~ "\r\n" ~ toBulk(command) ~ buffer[];
}

/**
 Take an array of strings and concat them to a single Multibulk

 Examples:

 ---
 toMultiBulk(["SET", "name", "adil"]) == toMultiBulk("SET name adil")
 ---
 */
@trusted auto toMultiBulk(C)(const C[][] commands) if (isSomeChar!C)
{
	auto buffer = appender!(C[])();
	buffer.reserve(commands.length * 50);

	buffer ~= "*" ~ to!(C[])(commands.length) ~ "\r\n";

	foreach(c; commands) {
		buffer ~= toBulk(c);
	}

	return buffer[];
}

/**
 * Take a Redis command (w|d)string and convert it to a MultiBulk
 */
@trusted auto toMultiBulk(C)(const C[] command) if (isSomeChar!C)
{
	alias command str;

	size_t
		start,
		end,
		bulk_count;

	auto buffer = appender!(C[])();
	buffer.reserve(cast(size_t)(command.length * 1.2)); //Reserve for 20% overhead.

	C c;

	for(size_t i = 0; i < str.length; i++) {
		c = str[i];

		/**
		 * Special support for quoted string so that command line support for
		 	proper use of EVAL is available.
		*/
		if(c == '"' || c == '\'') {
			start = i+1;

			//Circuit breaker to avoid RangeViolation
			while(++i < str.length
				&& (str[i] != c || (str[i] == c && str[i-1] == '\\'))
				){}

			goto MULTIBULK_PROCESS;
		}

		if(c != ' ')
			continue;

		// c is a ' ' (space) here
		if(i == start) {
			start++;
			end++;
			continue;
		}

		MULTIBULK_PROCESS:
		end = i;
		buffer ~= toBulk(str[start .. end]);
		start = end + 1;
		bulk_count++;
	}

	//Nothing found? That means the string is just one Bulk
	if(!buffer[].length) {
		buffer ~= toBulk(str);
		bulk_count++;
	}
	//If there's anything leftover, push it
	else if(end+1 < str.length) {
		buffer ~= toBulk(str[end+1 .. $]);
		bulk_count++;
	}

	return "*%d\r\n%s".format(bulk_count, buffer[]);
}

@trusted auto toBulk(C)(const C[] str) if (isSomeChar!C)
{
	return "$%d\r\n%s\r\n".format(str.length, str);
}

debug(tinyredis) @trusted C[] escape(C)(C[] str) if (isSomeChar!C)
{
	import std.string : replace;
	return str.replace("\r\n", "\\r\\n");
}

private:

@trusted uint accumulator(C, T...)(Appender!(C[]) w, T args)
{
	uint ctr;

	static foreach (i, arg; args) {
		static if(isSomeString!(T[i])) {
			w ~= toBulk(arg);
			ctr++;
		} else static if(isArray!(T[i])) {
			foreach(a; arg)
				ctr += accumulator(w, a);
		} else {
			w ~= toBulk(text(arg));
			ctr++;
		}
	}

	return ctr;
}

unittest {

	assert(toBulk("$2") == "$2\r\n$2\r\n");
	assert(encode("GET *2") == "*2\r\n$3\r\nGET\r\n$2\r\n*2\r\n");
	assert(encode("TTL myset") == "*2\r\n$3\r\nTTL\r\n$5\r\nmyset\r\n");
	assert(encode("TTL", "myset") == "*2\r\n$3\r\nTTL\r\n$5\r\nmyset\r\n");

	enum lua = "return redis.call('set','foo','bar')";
	assert(encode("EVAL \"" ~ lua ~ "\" 0") == "*3\r\n$4\r\nEVAL\r\n$"~to!string(lua.length)~"\r\n"~lua~"\r\n$1\r\n0\r\n");

	assert(encode("\"" ~ lua ~ "\" \"" ~ lua ~ "\" ") == "*2\r\n$"~to!string(lua.length)~"\r\n"~lua~"\r\n$"~to!string(lua.length)~"\r\n"~lua~"\r\n");
	assert(encode("eval \"" ~ lua ~ "\" " ~ "0") == encode("eval", lua, 0));

	assert(encode("SREM", ["myset", "$3", "$4", "two words"]) == encode("SREM myset $3 $4 'two words'"));
	assert(encode("SREM", "myset", "$3", "$4", "two words")   == encode("SREM myset $3 $4 'two words'"));
	assert(encode(["SREM", "myset", "$3", "$4", "two words"]) == encode("SREM myset $3 $4 'two words'"));

	assert(encode("SADD", "numbers", [1,2,3]) == encode("SADD numbers 1 2 3"));
	assert(encode("SADD", "numbers", 1,2,3, [4,5]) == encode("SADD numbers 1 2 3 4 5"));
	assert(encode("TTL", "myset") == encode("TTL myset"));
	assert(encode("TTL", "myset") == encode("TTL", ["myset"]));

	assert(encode("ZADD", "mysortedset", 1, "{\"a\": \"b\"}") == "*4\r\n$4\r\nZADD\r\n$11\r\nmysortedset\r\n$1\r\n1\r\n$10\r\n{\"a\": \"b\"}\r\n");
	assert(encode("ZADD", "mysortedset", "1", "{\"a\": \"b\"}") == "*4\r\n$4\r\nZADD\r\n$11\r\nmysortedset\r\n$1\r\n1\r\n$10\r\n{\"a\": \"b\"}\r\n");
}
