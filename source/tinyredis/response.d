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
	import std.conv : to;

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
	 * Allows casting a Response to an integral, bool or string
	 */
	T opCast(T)()
	if(is(T == bool)
	|| is(T == byte)
	|| is(T == short)
	|| is(T == int)
	|| is(T == long)
	|| is(T == string))
	{
		static if(is(T == bool))
			return toBool;
		else static if(is(T == byte) || is(T == short) || is(T == int) || is(T == long))
			return toInt!T;
		else static if(is(T == string))
			return toString;
	}

	/**
	 * Allows casting a Response to (u)byte[]
	 */
	C[] opCast(C : C[])() if(is(C == byte) || is(C == ubyte))
	{
		return toBytes!(C);
	}

@property @trusted:

	/**
	 * Attempts to convert a response to an array of bytes
	 *
	 * For intvals - converts to an array of bytes that is Response.intval.sizeof long
	 * For Bulk - casts the string to C[]
	 *
	 * Returns an empty array in all other cases;
	 */
	C[] toBytes(C)() if(is(C == byte) || is(C == ubyte))
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
	 * Attempts to check for truthiness of a Response.
	 *
	 * Returns false on failure.
	 */
	bool toBool()
	{
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
	 * Converts a Response to an integral (byte to long)
	 *
	 * Only works with ResponseType.Integer and ResponseType.Bulk
	 *
	 * Throws : ConvOverflowException, RedisCastException
	 */
	T toInt(T = int)()
	if(is(T == byte) || is(T == short) || is(T == int) || is(T == long))
	{
		import std.conv : ConvOverflowException;

		switch(type)
		{
			case ResponseType.Integer:
				if(intval <= T.max)
					return cast(T)intval;
				throw new ConvOverflowException("Cannot convert " ~ intval.to!string ~ " to " ~ T.stringof);

			case ResponseType.Bulk:
				try
					return to!T(value);
				catch(ConvOverflowException e)
				{
					e.msg = "Cannot convert " ~ value ~ " to " ~ T.stringof;
					throw e;
				}

			default:
				throw new RedisCastException("Cannot cast " ~ type ~ " to " ~ T.stringof);
		}
	}

	/**
	 * Returns the value of this Response as a string
	 */
	string toString()
	{
		import std.conv : text;

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

/* ----------- EXCEPTIONS ------------- */

class RedisCastException : Exception {
	this(string msg) { super(msg); }
}