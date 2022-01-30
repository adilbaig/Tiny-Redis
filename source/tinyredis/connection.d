module tinyredis.connection;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

import std.socket : TcpSocket;
version(Windows) import core.sys.windows.winsock2: EWOULDBLOCK;

import std.string : format;
import
	tinyredis.decoder,
	tinyredis.response;

debug(tinyredis) {
	import std.stdio : writeln;
	import tinyredis.encoder : escape;
}

/**
 * Sends a pre-encoded string
 *
 * Params:
 *   conn     	 = Connection to redis server.
 *   encoded_cmd = The command to be sent.
 *
 * Throws: $(D ConnectionException) if sending fails.
 */
void send(TcpSocket conn, string encoded_cmd)
{
	debug(tinyredis) writeln("Request : '", escape(encoded_cmd), "'");

	if (conn.send(encoded_cmd) != encoded_cmd.length)
		throw new ConnectionException("Error while sending request");
}

/**
 * Receive responses from redis server
 *
 * Params:
 *   conn    	  = Connection to redis server.
 *   minResponses = The number of multibulks you expect
 *
 * Throws: $(D ConnectionException) if there is a socket error or server closes the connection.
 */
Response[] receiveResponses(TcpSocket conn, size_t minResponses = 0)
{
	import std.array : back, popBack;

	char[] buffer;
	Response[] responses;

	Response*[] MultiBulks; //Stack of pointers to multibulks
	Response[]* stackPtr = &responses; // This is the stack where new elements are pushed

	for(;;)
	{
		receive(conn, buffer);

		while(buffer.length)
		{
			auto r = parseResponse(buffer);
			if(r.type == ResponseType.Invalid) // This occurs when the buffer is incomplete. Pull more
				break;

			*stackPtr ~= r;
			if(r.type == ResponseType.MultiBulk && r.count > 0)
			{
				auto mb = &(*stackPtr)[$-1];
				MultiBulks ~= mb;
				stackPtr = &(*mb).values;
			}

			while(MultiBulks.length)
			{
				auto mb = *MultiBulks.back;

				if(mb.count != mb.values.length)
					break;

				MultiBulks.popBack();
				stackPtr = MultiBulks.length ? &(*MultiBulks.back).values : &responses;
			}
		}

		if(buffer.length == 0 && MultiBulks.length == 0) //Make sure all the multi bulks got their data
		{
			debug(tinyredis)
				if(minResponses > 1 && responses.length < minResponses)
					writeln("WAITING FOR MORE RESPONSES ... ");

			if(responses.length >= minResponses)
				break;
		}
	}

	return responses;
}

/* -------- EXCEPTIONS ------------- */

class ConnectionException : Exception {
	this(string msg) { super(msg); }
}

private void receive(TcpSocket conn, ref char[] buffer)
{
	import core.stdc.errno;

	char[16 << 10] buff = void;
	size_t len = conn.receive(buff);

	if (conn.blocking)
	{
		if(len == 0)
			throw new ConnectionException("Server closed the connection!");
		if(len == TcpSocket.ERROR)
			throw new ConnectionException("A socket error occurred!");
	}
	else if (len == -1)
	{
		if (errno != EWOULDBLOCK)
			throw new ConnectionException("A socket error occurred! errno: %s".format(errno));

		len = 0;
		errno = 0;
	}

	buffer ~= buff[0 .. len];
	debug(tinyredis) writeln("Response : '", escape(cast(string)buffer), "'", " Length : ", len);
}
