module tinyredis.response;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

import std.conv : to;

enum CRLF = "\r\n";

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
	int count; //Used for multibulk only. -1 is a valid multibulk. Indicates nil

	private int curr;

	union{
		string value;
		long intval;
		Response[] values;
	}

	@property bool isString() const
	{
		return type == ResponseType.Bulk;
	}

	@property bool isInt() const
	{
		return type == ResponseType.Integer;
	}

	@property bool isArray() const
	{
		return type == ResponseType.MultiBulk;
	}

	@property bool isError() const
	{
		return type == ResponseType.Error;
	}

	@property bool isNil() const
	{
		return type == ResponseType.Nil;
	}

	@property bool isStatus() const
	{
		return type == ResponseType.Status;
	}

	@property bool isValid() const
	{
		return type != ResponseType.Invalid;
	}

	/*
	 * Response is a BidirectionalRange
	 */
	@property bool empty()
	{
		if(!isArray()) {
			return true;
		}

		return curr == values.length;
	}

	@property auto front()
	{
		return values[curr];
	}

	@property void popFront()
	{
		curr++;
	}

	@property auto back()
	{
		return values[values.length - 1];
	}

	@property void popBack()
	{
		curr--;
	}

	// Response is a ForwardRange
	@property auto save()
	{
		// Returning a copy of this struct object
		return this;
	}

	/**
	 * Support foreach(k, v; response)
	 */
	int opApply(int delegate(size_t, Response) dg)
	{
		if(!isArray()) {
			return 1;
		}

		foreach(k, v; values) {
			dg(k, v);
		}

		return 0;
	}

	/**
	 * Support foreach_reverse(k, v; response)
	 */
	int opApplyReverse(int delegate(size_t, Response) dg)
	{
		if(!isArray()) {
			return 1;
		}

		foreach_reverse(k, v; values) {
			dg(k, v);
		}

		return 0;
	}

	/**
	 * Support foreach(v; response)
	 */
	int opApply(int delegate(Response) dg)
	{
		if(!isArray()) {
			return 1;
		}

		foreach(v; values) {
			dg(v);
		}

		return 0;
	}

	/**
	 * Support foreach_reverse(v; response)
	 */
	int opApplyReverse(int delegate(Response) dg)
	{
		if(!isArray()) {
			return 1;
		}

		foreach_reverse(v; values) {
			dg(v);
		}

		return 0;
	}

	/**
	 * Allows casting a Response to an integral, bool or string
	 */
	T opCast(T)()
	if(is(T == bool)
			|| is(T == byte)
			|| is(T == short)
			|| is(T == int)
			|| is(T == long)
			|| is(T == string)
			)
	{
		static if(is(T == bool))
			return toBool();
		else static if(is(T == byte) || is(T == short) || is(T == int) || is(T == long))
			return toInt!T();
		else static if(is(T == string))
			return toString();
	}

	/**
	 * Allows casting a Response to (u)byte[]
	 */
	C[] opCast(C : C[])() if(is(C == byte) || is(C == ubyte))
	{
		return toBytes!(C)();
	}

	/**
	 * Attempts to convert a response to an array of bytes
	 *
	 * For intvals - converts to an array of bytes that is Response.intval.sizeof long
	 * For Bulk - casts the string to C[]
	 *
	 * Returns an empty array in all other cases;
	 */
	@property @trusted C[] toBytes(C)() if(is(C == byte) || is(C == ubyte))
	{
		import std.array;

		switch(type)
		{
			case ResponseType.Integer:
				C[] ret = uninitializedArray!(C[])(intval.sizeof);
				C* bytes = cast(C*)&intval;
				for(int i = 0; i < intval.sizeof; i++)
					ret[i] = bytes[i];

				return ret;

			case ResponseType.Bulk:
				return cast(C[])value;

			default:
				return [];
		}
	}

	/**
	 * Attempts to check for truthiness of a Response.
	 *
	 * Returns false on failure.
	 */
	@property @trusted bool toBool()
	{
		switch(type)
		{
			case ResponseType.Integer:
				return intval > 0;

			case ResponseType.Status:
				return value == "OK";

			case ResponseType.Bulk:
				return value.length > 0;

			case ResponseType.MultiBulk:
				return values.length > 0;

			default:
				return false;
		}
	}

	/**
	 * Converts a Response to an integral (byte to long)
	 *
	 * Only works with ResponseType.Integer and ResponseType.Bulk
	 *
	 * Throws : ConvOverflowException, RedisCastException
	 */
	@property @trusted T toInt(T = int)()
	if(is(T == byte) || is(T == short) || is(T == int) || is(T == long))
	{
		import std.conv : ConvOverflowException;

		switch(type)
		{
			case ResponseType.Integer:
				if(intval <= T.max)
					return cast(T)intval;
				else
					throw new ConvOverflowException("Cannot convert " ~ intval.to!string ~ " to " ~ typeid(T).to!string);

			case ResponseType.Bulk:
				try{
					return to!T(value);
				}catch(ConvOverflowException e)
				{
					e.msg = "Cannot convert " ~ value ~ " to " ~ typeid(T).to!string;
					throw e;
				}

			default:
				throw new RedisCastException("Cannot cast " ~ type ~ " to " ~ typeid(T).to!string);
		}
	}

	/**
	 * Returns the value of this Response as a string
	 */
	@property @trusted string toString()
	{
		import std.conv : text;

		switch(type)
		{
			case ResponseType.Integer:
				return intval.to!string;

			case ResponseType.Error:
			case ResponseType.Status:
			case ResponseType.Bulk:
				return value;

			case ResponseType.MultiBulk:
				return text(values);

			default:
				return "";
		}
	}

	/**
	 * Returns the value of this Response as a string, along with type information
	 */
	@property @trusted string toDiagnosticString()
	{
		import std.array : appender;

		final switch(type)
		{
			case ResponseType.Nil:
				return "(Nil)";

			case ResponseType.Error:
				return "(Err) " ~ value;

			case ResponseType.Integer:
				return "(Integer) " ~ intval.to!string;

			case ResponseType.Status:
				return "(Status) " ~ value;

			case ResponseType.Bulk:
				return value;

			case ResponseType.MultiBulk:

				auto t = appender!string();

				foreach(v; values)
					t ~= v.toDiagnosticString();

				return t[];

			case ResponseType.Invalid:
				return "(Invalid)";
		}
	}
}

/* ----------- EXCEPTIONS ------------- */

class RedisCastException : Exception {
	this(string msg) { super(msg); }
}