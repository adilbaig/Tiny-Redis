module tinyredis.encoder;

private :
	import std.string : format, strip;
	import std.array;
	import std.traits;
	import std.conv;

public:

alias toMultiBulk encode;

@trusted C[] toMultiBulk(C, A)(const C[] command, A[] args) if (isSomeChar!C)
{
	C[] buffer = command.dup;
	
	foreach(b; args) {
        buffer ~= ' ' ~ text(b);
    }
    
    return toMultiBulk(buffer);
}

@trusted C[] toMultiBulk(C, T...)(const C[] command, T args) if (isSomeChar!C)
{
	C[] buffer = command.dup;
	
	static if(!is(T == immutable(char)[])) {
        foreach(b; args) {
            buffer ~= ' ' ~ text(b);
        }
    } else {
    	buffer ~= ' ' ~ text(args);
    }
    
    return toMultiBulk(buffer);
}

@trusted C[] toMultiBulk(C)(const C[][] commands) if (isSomeChar!C)
{
	auto appender = appender!(C[])();
	appender.reserve(commands.length * 10);
    foreach(c; commands)
        appender ~= toBulk(c);
	
	return "*" ~ to!(C[])(commands.length) ~ "\r\n" ~ appender.data;
}

@trusted C[] toMultiBulk(C)(const C[] command) if (isSomeChar!C)
{
    auto str = strip(command);
    
	size_t 
		start, 
		end,
		bulk_count;
	C[] buffer;
	C c;

    for(size_t i = 0; i < str.length; i++) {
    	c = str[i];
    	
    	if((c == '"' || c == '\'') && i > 0 && str[i-1] != '\\') {
			i = endOfEvalString(str[i .. $]) + i + 1;
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
	if(!buffer.length)  {
		buffer = toBulk(str);
		bulk_count++;
	}
	//If there's anything leftover, push it
	else if(end+1 < str.length) {
		buffer ~= toBulk(str[end+1 .. $]);
		bulk_count++;
	}

	return format!(C)("*%d\r\n%s", bulk_count, buffer);
}

@trusted C[] toBulk(C)(const C[] str) if (isSomeChar!C)
{
    return format!(C)("$%d\r\n%s\r\n", str.length, str);
}

private pure size_t endOfEvalString(C)(const C[] sub_command) if (isSomeChar!C)
{
	C startChar;
	foreach(i, c; sub_command) {
		if(i == 0) {
			startChar = c;
			continue;
		}
		
		if(c == startChar && sub_command[i-1] != '\\') {
			return i;
		}
	}

	throw new Exception("Unclosed string");
}

debug :
	@trusted C[] escape(C)(C[] str) if (isSomeChar!C)
	{
	     return replace(str,"\r\n","\\r\\n");
	}
