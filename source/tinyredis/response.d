module tinyredis.response;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

package enum CRLF = "\r\n";

enum ResponseType : byte
{
	Invalid,
	Status,
	Error,
	Integer,
	Bulk,
	MultiBulk,
	Nil
}

/**
 * The Response struct represents returned data from Redis.
 *
 * Stores values true to form. Allows user code to query, cast, iterate, print, and log strings, ints, errors and all other return types.
 *
 * The role of the Response struct is to make it simple, yet accurate to retrieve returned values from Redis. To aid this
 * it implements D op* functions as well as little helper methods that simplify user facing code.
 */
struct Response
{
	ResponseType type;
	union {
		struct {
			Response[] values;
			int count; //Used for multibulk only. -1 is a valid multibulk. Indicates nil
		}
		struct {
			size_t length;
			union {
				string value;
				long intval;
			}
		}
	}

	alias values this;

	@property nothrow @nogc {
		bool isString() const { return type == ResponseType.Bulk; }

		bool isInt() const { return type == ResponseType.Integer; }

		bool isArray() const { return type == ResponseType.MultiBulk; }

		bool isError() const { return type == ResponseType.Error; }

		bool isNil() const { return type == ResponseType.Nil; }

		bool isStatus() const { return type == ResponseType.Status; }

		bool isValid() const { return type != ResponseType.Invalid; }

		// Response is a ForwardRange
		auto save()
		{
			// Returning a copy of this struct object
			return this;
		}
	}

	/**
	 * Parse a char array into a Response struct.
	 *
	 * The parser works to identify a minimum complete Response. If successful, it removes that chunk from "mb" and returns a Response struct.
	 * On failure it returns a `ResponseType.Invalid` Response and leaves "mb" untouched.
	 */
	static Response parse(ref char[] mb) nothrow @nogc @trusted
	{
		Response resp;
		if(mb.length < 4)
			return resp;

		char c = mb[0];
		mb = mb[1..$];
		switch(c)
		{
			case '+':
				if (!mb.tryParse(resp.value))
					return resp;

				resp.type = ResponseType.Status;
				break;

			case '-':
				if (!mb.tryParse(resp.value))
					return resp;

				resp.type = ResponseType.Error;
				break;

			case ':':
				if (!mb.tryParse(resp.intval))
					return resp;

				resp.type = ResponseType.Integer;
				break;

			case '$':
				int l = void;
				if (!mb.tryParse(l))
					return resp;

				if(l == -1)
				{
					resp.type = ResponseType.Nil;
					break;
				}

				if(l + 2 > mb.length) //We don't have enough data. Let's return an invalid resp.
					return resp;

				resp.value = cast(string)mb[0..l];
				resp.type = ResponseType.Bulk;
				mb = mb[l+2..$];
				break;

			case '*':
				int l = void;
				if (!mb.tryParse(l))
					return resp;

				if(l == -1)
				{
					resp.type = ResponseType.Nil;
					break;
				}

				resp.type = ResponseType.MultiBulk;
				resp.count = l;
				break;

			default:
				break;
		}

		return resp;
	}

	/**
	 * Attempts to check for truthiness of a Response.
	 *
	 * Returns false on failure.
	 */
	T opCast(T : bool)() {
		switch(type) with(ResponseType)
		{
			case Integer:	return intval > 0;
			case Status:	return value == "OK";
			case Bulk:		return value.length != 0;
			case MultiBulk: return values.length != 0;
			default:		return false;
		}
	}

	/**
	 * Allows casting a Response to an integral or string
	 */
	T opCast(T)() if(is(T : long) || is(T == string))
	{
		static if(is(T : long))
			return toInt!T;
		else
			return toString;
	}

	/**
	 * Attempts to convert a response to an array of bytes
	 *
	 * For intvals - converts to an array of bytes that is Response.intval.sizeof long
	 * For Bulk - casts the string to C[]
	 *
	 * Returns an empty array in all other cases;
	 */
	C[] opCast(C : C[])() if(is(C == byte) || is(C == ubyte))
	{
		import std.array;

		switch(type)
		{
			case ResponseType.Integer:
				C[] ret = uninitializedArray!(C[])(intval.sizeof);
				*cast(long*)ret.ptr = intval;
				return ret;

			case ResponseType.Bulk:
				return cast(C[])value;

			default:
				return [];
		}
	}

	/**
	 * Converts a Response to an integral (byte to long)
	 *
	 * Only works with ResponseType.Integer and ResponseType.Bulk
	 *
	 * Throws : ConvOverflowException, RedisCastException
	 */
	T toInt(T = int)() if(is(T : long))
	{
		import std.conv;

		switch(type)
		{
			case ResponseType.Integer:
				if(intval <= T.max)
					return cast(T)intval;
				throw new ConvOverflowException("Cannot convert " ~ intval.to!string ~ " to " ~ T.stringof);

			case ResponseType.Bulk:
				try
					return value.to!T;
				catch(ConvOverflowException e)
				{
					e.msg = "Cannot convert " ~ value ~ " to " ~ T.stringof;
					throw e;
				}

			default:
				throw new RedisCastException("Cannot cast " ~ type ~ " to " ~ T.stringof);
		}
	}

@property @trusted:
	/**
	 * Returns the value of this Response as a string
	 */
	string toString()
	{
		import std.conv;

		switch(type) with(ResponseType)
		{
			case Integer:
				return intval.to!string;

			case Error:
			case Status:
			case Bulk:
				return value;

			case MultiBulk:
				return text(values);

			default:
				return "";
		}
	}

	/**
	 * Returns the value of this Response as a string, along with type information
	 */
	string toDiagnosticString()
	{
		import std.array : appender;
		auto app = appender!string;
		toDiagnosticString(app);
		return app[];
	}

	void toDiagnosticString(R)(ref R appender)
	{
		import std.conv : to;
		final switch(type) with(ResponseType)
		{
		case Invalid:	appender.put("(Invalid)");	break;
		case Nil:		appender.put("(Nil)");		break;
		case Error:
			appender.put("(Err) ");
			goto case Bulk;
		case Integer:
			appender.put("(Integer) ");
			appender.put(intval.to!string);
			break;
		case Status:
			appender.put("(Status) ");
			goto case;
		case Bulk:
			appender.put(value);
			break;
		case MultiBulk:
			foreach(v; values)
				v.toDiagnosticString(appender);
			break;
		}
	}
}

unittest
{
	import std.range : isInputRange, isForwardRange, isBidirectionalRange;

	//Testing ranges for Response
	static assert(isInputRange!Response);
	static assert(isForwardRange!Response);
	static assert(isBidirectionalRange!Response);
}

/* ----------- EXCEPTIONS ------------- */

class RedisCastException : Exception {
	this(string msg) { super(msg); }
}

import std.traits;

bool tryParse(T)(ref char[] data, out T x) if(isIntegral!T)
in (data.length) {
	T f = 1;
	size_t i;
	char c = data[0];
	if (c == '-') {
		f = -1;
		i = 1;
	}
	for(; i < data.length; ++i) {
		c = data[i];
		if (c < '0' || c > '9')
			break;
		x = x * 10 + (c ^ '0');
		if (x < 0)
			return false;
	}
	x *= f;
	++i;
	if(c != '\r' || i >= data.length || data[i] != '\n')
		return false;

	data = data[i+1..$];
	return true;
}

bool tryParse(T)(ref char[] data, out T x) if(isSomeString!T) {
	import std.string;

	auto i = indexOf(data, '\r');
	if (i < 0 || i + 1 >= data.length || data[i + 1] != '\n')
		return false;

	x = cast(T)data[0..i];
	data = data[i+2..$];
	return true;
}

unittest
{
	alias parse = Response.parse;

	//Test Nil bulk
	auto stream = cast(char[])"$-1\r\n";
	auto resp = parse(stream);
	assert(resp.toString == "");
	assert(!resp);
	try{
		cast(int)resp;
		assert(0);
	}
	catch(RedisCastException) {}

	//Test Nil multibulk
	stream = cast(char[])"*-1\r\n";
	resp = parse(stream);
	assert(resp.toString == "");
	assert(!resp);
	try{
		cast(int)resp;
		assert(0);
	}
	catch(RedisCastException) {}

	//Empty Bulk
	stream = cast(char[])"$0\r\n\r\n";
	resp = parse(stream);
	assert(resp.toString == "");
	assert(!resp);

	stream = cast(char[])"*4\r\n$3\r\nGET\r\n$1\r\n*\r\n:123\r\n+A Status Message\r\n";

	resp = parse(stream);
	assert(resp.type == ResponseType.MultiBulk);
	assert(resp.count == 4);
	assert(resp.values.length == 0);

	resp = parse(stream);
	assert(resp.type == ResponseType.Bulk);
	assert(resp.value == "GET");
	assert(cast(string)resp == "GET");

	resp = parse(stream);
	assert(resp.type == ResponseType.Bulk);
	assert(resp.value == "*");
	assert(resp);

	resp = parse(stream);
	assert(resp.type == ResponseType.Integer);
	assert(resp.intval == 123);
	assert(cast(string)resp == "123");
	assert(cast(int)resp == 123);

	resp = parse(stream);
	assert(resp.type == ResponseType.Status);
	assert(resp.value == "A Status Message");
	assert(cast(string)resp == "A Status Message");
	try {
		cast(int)resp;
		assert(0, "Tried to convert string to int");
	} catch(RedisCastException) {}

	//Stream should have been used up, verify
	assert(stream.length == 0);
	assert(parse(stream).type == ResponseType.Invalid);

	import std.conv : ConvOverflowException;
	//Long overflow checking
	stream = cast(char[])":9223372036854775808\r\n";
	resp = parse(stream);
	assert(resp.type == ResponseType.Invalid, "Tried to convert long.max+1 to long");

	Response r = {type : ResponseType.Bulk, value : "9223372036854775807"};
	try{
		r.toInt(); //Default int
		assert(0, "Tried to convert long.max to int");
	}
	catch(ConvOverflowException) {}

	r.value = "127";
	assert(r.toInt!byte() == 127);
	assert(r.toInt!short() == 127);
	assert(r.toInt() == 127);
	assert(r.toInt!long() == 127);

	stream = cast(char[])"*0\r\n";
	resp = parse(stream);
	assert(resp.count == 0);
	assert(resp.values.length == 0);
	assert(resp.values == []);
	assert(resp.toString == "[]");
	assert(!resp);
	try
		cast(int)resp;
	catch(RedisCastException) {}

	//Testing opApply
	stream = cast(char[])"*0\r\n";
	resp = parse(stream);
	foreach(k, v; resp)
		assert(0, "opApply is broken");
	foreach(v; resp)
		assert(0, "opApply is broken");

	stream = cast(char[])"$2\r\n$2\r\n";
	resp = parse(stream);
	foreach(k, v; resp)
		assert(0, "opApply is broken");
	foreach(v; resp)
		assert(0, "opApply is broken");

	stream = cast(char[])":1000\r\n";
	resp = parse(stream);
	foreach(k, v; resp)
		assert(0, "opApply is broken");
	foreach(v; resp)
		assert(0, "opApply is broken");

	//Testing opApplyReverse
	stream = cast(char[])"*0\r\n";
	resp = parse(stream);
	foreach_reverse(k, v; resp)
		assert(0, "opApplyReverse is broken");
	foreach_reverse(v; resp)
		assert(0, "opApplyReverse is broken");
}