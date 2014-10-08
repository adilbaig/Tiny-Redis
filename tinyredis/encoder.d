module tinyredis.encoder;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

private :
	import std.string : format, strip;
	import std.array;
	import std.traits;
	import std.conv;
        import std.regex;

        string[] redisScriptCommands = [
	  "EVAL", // and "EVALSHA"
	  "SCRIPT EXISTS",
	  "SCRIPT FLUSH",
	  "SCRIPT KILL",
	  "SCRIPT LOAD"
	];

public:

alias toMultiBulk encode;

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
	
    buffer ~= command;
	
	foreach (i; args) {
		buffer ~= ' ' ~ i;
	}
	
	return toMultiBulk(buffer.data);
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
    buffer ~= command;
    accumalator!(C,T)(buffer, args);
    return toMultiBulk(buffer.data);
}
 
/**
 Take an array of strings and concat them to a single Multibulk
 
 Examples:
 
 ---
 toMultiBulk("SET", "name", "adil") == toMultiBulk("SET name adil")
 ---
 */
@trusted auto toMultiBulk(C)(const C[][] commands) if (isSomeChar!C)
{
	auto buffer = appender!(C[])();
	buffer.reserve(commands.length * 100);
	
	buffer ~= "*";
	buffer ~= to!(C[])(commands.length);
	buffer ~= "\r\n";
	
    foreach(c; commands)
        buffer ~= toBulk(c);
	
	return buffer.data;
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
//	debug std.stdio.writeln("COMMAND LENGTH : ", command.length, " BUFFER : ", buffer.capacity);
	
	C c;

    for(size_t i = 0; i < str.length; i++) {
    	c = str[i];
    	
    	/**
    	 * Special support for quoted string so that command line support for 
    	 	proper use of EVAL is available.
    	*/
    	if((c == '"' || c == '\'')) {
    		start = i+1;
//			debug std.stdio.writeln("START : ", start, " LENGTH : ", str.length);
			
			//Circuit breaker to avoid RangeViolation
    		while(++i < str.length
    			&& (str[i] != c || (str[i] == c && str[i-1] == '\\'))
    			){}
    		
//    		debug std.stdio.writeln("QUOTED STRING : ", str[start .. i]);
			goto MULTIBULK_PROCESS;
		}
    	
    	if(c != ' ') {
			continue;
		}
    	
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
	if(!buffer.data.length)  {
		buffer ~= toBulk(str);
		bulk_count++;
	}
	//If there's anything leftover, push it
	else if(end+1 < str.length) {
		buffer ~= toBulk(str[end+1 .. $]);
		bulk_count++;
	}

	return format!(C)("*%d\r\n%s", bulk_count, buffer.data);
}

@trusted auto toBulk(C)(const C[] str) if (isSomeChar!C)
{
    return format!(C)("$%d\r\n%s\r\n", str.length, str);
}

private @trusted void accumalator(C, T...)(Appender!(C[]) w, T args)
{
	foreach (i, arg; args) {
		static if(isSomeString!(typeof(arg))) {
		    if(isRedisScript(to!string(w.data))) {
		        w ~= ' '  ~ arg;
		    } else {
		        w ~= ' '  ~ "'" ~ arg ~ "'";
		    }
		} else static if(isArray!(typeof(arg))) {
			foreach(a; arg) {
				accumalator(w, a);
			}
		} else {
			w ~= ' ' ~ text(arg);
		}
    }
}

private @trusted bool isRedisScript(string s)
{
  foreach(command; redisScriptCommands) {
    auto match = matchFirst(s, regex(r"^" ~ command, "i"));
    if (match.captures.length > 0) {
      return true;
    }
  }
  return false;
}

debug @trusted C[] escape(C)(C[] str) if (isSomeChar!C)
{
     return replace(str,"\r\n","\\r\\n");
}
	
unittest {
	
    assert(toBulk("$2") == "$2\r\n$2\r\n");
    assert(encode("GET *2") == "*2\r\n$3\r\nGET\r\n$2\r\n*2\r\n");
    assert(encode("TTL myset") == "*2\r\n$3\r\nTTL\r\n$5\r\nmyset\r\n");
    assert(encode("TTL", "myset") == "*2\r\n$3\r\nTTL\r\n$5\r\nmyset\r\n");
    
    {
      import std.json;
      JSONValue json = parseJSON("{\"a\": \"b\"}");
      assert(toMultiBulk("ZADD", "test_key", 1, json.toString()) == "*4\r\n$4\r\nZADD\r\n$8\r\ntest_key\r\n$1\r\n1\r\n$9\r\n{\"a\":\"b\"}\r\n");
    }

    auto lua = "return redis.call('set','foo','bar')";
    assert(encode("EVAL \"" ~ lua ~ "\" 0") == "*3\r\n$4\r\nEVAL\r\n$"~to!(string)(lua.length)~"\r\n"~lua~"\r\n$1\r\n0\r\n");

    assert(encode("\"" ~ lua ~ "\" \"" ~ lua ~ "\" ") == "*2\r\n$"~to!(string)(lua.length)~"\r\n"~lua~"\r\n$"~to!(string)(lua.length)~"\r\n"~lua~"\r\n");
    assert(encode("eval \"" ~ lua ~ "\" " ~ "0") == encode("eval", "\"" ~ lua ~ "\"", 0));
    
    assert(encode("SREM", ["myset", "$3", "$4"]) == encode("SREM myset $3 $4"));
    assert(encode("SREM", "myset", "$3", "$4")   == encode("SREM myset $3 $4"));
    assert(encode(["SREM", "myset", "$3", "$4"]) == encode("SREM myset $3 $4"));
    
    assert(encode("SADD", "numbers", [1,2,3]) == encode("SADD numbers 1 2 3"));
    assert(encode("SADD", "numbers", 1,2,3, [4,5]) == encode("SADD numbers 1 2 3 4 5"));
    assert(encode("TTL", "myset") == encode("TTL myset"));
    assert(encode("TTL", "myset") == encode("TTL", ["myset"]));	
}
