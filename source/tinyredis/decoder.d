module tinyredis.decoder;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

import tinyredis.response;


/**
 * Parse a byte stream into a Response struct.
 *
 * The parser works to identify a minimum complete Response. If successful, it removes that chunk from "mb" and returns a Response struct.
 * On failure it returns a `ResponseType.Invalid` Response and leaves "mb" untouched.
 */
@trusted Response parseResponse(ref char[] mb)
{
	Response resp = { ResponseType.Invalid };

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
	//Test Nil bulk
	auto stream = cast(char[])"$-1\r\n";
	auto resp = parseResponse(stream);
	assert(resp.toString == "");
	assert(!resp.toBool);
	assert(!cast(bool)resp);
	try{
		cast(int)resp;
		assert(0);
	}
	catch(RedisCastException) {}

	//Test Nil multibulk
	stream = cast(char[])"*-1\r\n";
	resp = parseResponse(stream);
	assert(resp.toString == "");
	assert(!resp.toBool);
	assert(!cast(bool)resp);
	try{
		cast(int)resp;
		assert(0);
	}
	catch(RedisCastException) {}

	//Empty Bulk
	stream = cast(char[])"$0\r\n\r\n";
	resp = parseResponse(stream);
	assert(resp.toString == "");
	assert(!resp.toBool);
	assert(!resp);

	stream = cast(char[])"*4\r\n$3\r\nGET\r\n$1\r\n*\r\n:123\r\n+A Status Message\r\n";

	resp = parseResponse(stream);
	assert(resp.type == ResponseType.MultiBulk);
	assert(resp.count == 4);
	assert(resp.values.length == 0);

	resp = parseResponse(stream);
	assert(resp.type == ResponseType.Bulk);
	assert(resp.value == "GET");
	assert(cast(string)resp == "GET");

	resp = parseResponse(stream);
	assert(resp.type == ResponseType.Bulk);
	assert(resp.value == "*");
	assert(resp);

	resp = parseResponse(stream);
	assert(resp.type == ResponseType.Integer);
	assert(resp.intval == 123);
	assert(cast(string)resp == "123");
	assert(cast(int)resp == 123);

	resp = parseResponse(stream);
	assert(resp.type == ResponseType.Status);
	assert(resp.value == "A Status Message");
	assert(cast(string)resp == "A Status Message");
	try
		cast(int)resp;
	catch(RedisCastException)
	{
		//Exception caught
	}

	//Stream should have been used up, verify
	assert(stream.length == 0);
	assert(parseResponse(stream).type == ResponseType.Invalid);

	import std.conv : ConvOverflowException;
	//Long overflow checking
	stream = cast(char[])":9223372036854775808\r\n";
	resp = parseResponse(stream);
	assert(resp.type == ResponseType.Invalid, "Tried to convert long.max+1 to long");

	Response r = {type : ResponseType.Bulk, value : "9223372036854775807"};
	try{
		r.toInt(); //Default int
		assert(0, "Tried to convert long.max to int");
	}
	catch(ConvOverflowException)
	{
		//Ok, exception thrown as expected
	}

	r.value = "127";
	assert(r.toInt!byte() == 127);
	assert(r.toInt!short() == 127);
	assert(r.toInt() == 127);
	assert(r.toInt!long() == 127);

	stream = cast(char[])"*0\r\n";
	resp = parseResponse(stream);
	assert(resp.count == 0);
	assert(resp.values.length == 0);
	assert(resp.values == []);
	assert(resp.toString == "[]");
	assert(!resp.toBool);
	assert(!cast(bool)resp);
	try
		cast(int)resp;
	catch(RedisCastException) {}

	//Testing opApply
	stream = cast(char[])"*0\r\n";
	resp = parseResponse(stream);
	foreach(k, v; resp)
		assert(0, "opApply is broken");
	foreach(v; resp)
		assert(0, "opApply is broken");

	stream = cast(char[])"$2\r\n$2\r\n";
	resp = parseResponse(stream);
	foreach(k, v; resp)
		assert(0, "opApply is broken");
	foreach(v; resp)
		assert(0, "opApply is broken");

	stream = cast(char[])":1000\r\n";
	resp = parseResponse(stream);
	foreach(k, v; resp)
		assert(0, "opApply is broken");
	foreach(v; resp)
		assert(0, "opApply is broken");

	//Testing opApplyReverse
	stream = cast(char[])"*0\r\n";
	resp = parseResponse(stream);
	foreach_reverse(k, v; resp)
		assert(0, "opApplyReverse is broken");
	foreach_reverse(v; resp)
		assert(0, "opApplyReverse is broken");

	import std.range : isInputRange, isForwardRange, isBidirectionalRange;

	//Testing ranges for Response
	static assert(isInputRange!Response);
	static assert(isForwardRange!Response);
	static assert(isBidirectionalRange!Response);
}
