/**
 * Utilities for Redis Pub/Sub model
 *
 * Authors: Ali Çehreli, acehreli@yahoo.com
 * See_Also: https://redis.io/docs/manual/pubsub/
 */
module tinyredis.subscriber;

import tinyredis.connection;
import tinyredis.encoder : toMultiBulk;
import tinyredis.response : Response;
import std.stdio : stderr, writefln;
import std.array : empty, front, popFront;
import std.algorithm : find, any, min;
import std.conv : to;
import std.socket : InternetAddress;

// Regular subscription callback
alias Callback = void delegate(string channel, string message),

// Pattern subscription callback
	PCallback = void delegate(string pattern, string channel, string message);

/**
 * Whether a response is of a particular message type
 */
bool isType(string type)(Response r)
{
	return r.values[0].value == type;
}

class Subscriber
{
private:
	Transport conn;
	Callback[string] callbacks;      // Regular subscription callbacks
	PCallback[string] pCallbacks;    // Pattern subscription callbacks
	Response[][] queue;              // Responses collected but not yet processed

	/**
	 * Send a redis command.
	 */
	void send(string cmd)
	{
		// XXX - Do we need toMultiBulk here?
		conn.send(toMultiBulk(cmd));
	}

	/**
	 * Poll responses from the redis server and queue for later processing unless they match the
	 * predicate.
	 *
	 * This function is the workhorse behind all member functions of this type.
	 *
     * Params:
	 *   pred = The predicate function that determines whether a response is an expected one
	 *   expected = The number of responses expected to match the predicate
     *
	 * Returns:
     *   The last response that matched the predicate
	 */
	Response queueUnless(bool delegate(Response) pred, size_t expected = 1)
	{
		Response resp;
		size_t matched = 0;

		/* We will receive responses until all 'expected' responses are found. */

		// TODO - Timeout?
		while (matched < expected) {
			Response[] responses = receiveResponses(conn, 1);

			// This group may have zero or many matching responses

			while (!responses.empty) {
				auto found = responses.find!pred;

				// Enqueue older responses for later processing
				queue ~= responses[0 .. $ - found.length];

				if (found.empty)
					break;

				resp = found.front;
				responses = found[1 .. $];
				++matched;
			}
		}

		return resp;
	}

	/**
	 * Convenience wrapper for queueUnless(), which constructs a delegate from the provided message
	 * type.
	 */
	Response queueUnlessType(string type)(size_t expected = 1)
	{
		return queueUnless(r => r.isType!type, expected);
	}

	/**
	 * Process a single message
	 */
	void processMessage(Response resp)
	{
		auto elements = resp.values;

		/* Nested convenience function */
		void reportBadResponse()
		{
			stderr.writefln("Unexpected subscription response: %s", resp);
		}

		/* Nested convenience function returning response element at the specified index */
		string element(size_t index)
		{
			return elements[index].value;
		}

		string type = element(0);

		switch (type)
		{
		case "message":
			if (elements.length != 3) {
				reportBadResponse();
				break;
			}
			string channel = element(1);
			const callback = (channel in callbacks);

			if (callback)
			{
				string message = element(2);
				(*callback)(channel, message);
			}
			else
				stderr.writefln("No callback for message: %s", resp);
			break;

		case "pmessage":
			if (elements.length != 4) {
				reportBadResponse();
				break;
			}
			string pattern = element(1);
			const callback = (pattern in pCallbacks);

			if (callback) {
				string channel = element(2);
				string message = element(3);

				(*callback)(pattern, channel, message);
			}
			else
				stderr.writefln("No callback for pattern message: %s", resp);
			break;

		default:
			reportBadResponse();
			break;
		}
	}

public:

	/**
	 * Create a new non-blocking subscriber using a Redis host and port
	 */
	this(string host = "127.0.0.1", ushort port = 6379)
	{
		conn = new TcpTransport(new InternetAddress(host, port));
		conn.blocking = false;
	}

	/**
	 * Create a new subscriber using an existing socket
	 */
	this(Transport conn) { this.conn = conn; }

	/**
	 * Subscribe to a channel
	 *
	 * Returns the number of channels currently subscribed to
	 */
	size_t subscribe(string channel, Callback callback)
	{
		auto cmd = "SUBSCRIBE " ~ channel;
		send(cmd);

		Response resp = queueUnlessType!"subscribe"();
		callbacks[channel] = callback;

		return resp.values[2].to!int;
	}

	/**
	 * Subscribe to a channel pattern
	 *
	 * Returns the number of channels currently subscribed to
	 */
	size_t psubscribe(string pattern, PCallback callback)
	{
		auto cmd = "PSUBSCRIBE " ~ pattern;
		send(cmd);

		Response resp = queueUnlessType!"psubscribe"();
		pCallbacks[pattern] = callback;

		return resp.values[2].to!int;
	}

	/**
	 * Unsubscribe from a channel
	 *
	 * Returns the number of channels currently subscribed to
	 */
	size_t unsubscribe(string channel)
	{
		auto cmd = "UNSUBSCRIBE " ~ channel;
		send(cmd);

		Response resp = queueUnlessType!"unsubscribe"();
		callbacks.remove(channel);

		return resp.values[2].to!int;
	}

	/**
	 * Unsubscribe from all channels
	 *
	 * Returns the number of channels currently subscribed to
	 */
	size_t unsubscribe()
	{
		send("UNSUBSCRIBE");

		Response resp = queueUnlessType!"unsubscribe"(callbacks.length);
		callbacks = null;

		return resp.values[2].to!int;
	}

	/**
	 * Unsubscribe from a channel pattern
	 *
	 * Returns the number of channels currently subscribed to
	 */
	size_t punsubscribe(string pattern)
	{
		auto cmd = "PUNSUBSCRIBE " ~ pattern;
		send(cmd);

		Response resp = queueUnlessType!"punsubscribe"();
		pCallbacks.remove(pattern);

		return resp.values[2].to!int;
	}

	/**
	 * Unsubscribe from all channel patterns
	 *
	 * Returns the number of channels currently subscribed to
	 */
	size_t punsubscribe()
	{
		send("PUNSUBSCRIBE");

		Response resp = queueUnlessType!"punsubscribe"(pCallbacks.length);
		pCallbacks = null;

		return resp.values[2].to!int;
	}

	/**
	 * Close the redis connection
	 */
	Response quit()
	{
		send("QUIT");

		return queueUnless(r => r.value == "OK");
	}

	/**
	 * Send a PING command
	 */
	Response ping(string argument = null)
	{
		auto cmd = "PING " ~ argument;

		send(cmd);
		return queueUnless(r => r.isType!"pong");
	}

	/**
	 * Poll for queued messages on the redis server and call their callbacks
	 */
	void processMessages()
	{
		queue ~= receiveResponses(conn, 0);

		foreach (arr; queue) {
			foreach (resp; arr)
				processMessage(resp);
		}

		queue.length = 0;
		queue.assumeSafeAppend();
	}
}
