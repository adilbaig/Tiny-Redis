module tinyredis.subscriber;

/**
 * Authors: Ali Çehreli, acehreli@yahoo.com
 */

private:

import tinyredis.response : Response;
import tinyredis.encoder : toMultiBulk;
import tinyredis.connection : receiveResponses;
import std.socket : TcpSocket, InternetAddress, SocketShutdown;
import std.stdio : stderr, writefln;
import std.array : empty, front, popFront;
import std.algorithm : find, any, min;
import std.conv : to;

public:

// Regular subscription callback
alias Callback = void delegate(string channel, string message);

// Pattern subscription callback
alias PCallback = void delegate(string pattern, string channel, string message);

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
    TcpSocket conn;
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
     * predicate. Return the last matching response.
     */
    Response queueExcept(bool delegate(Response) pred, size_t expected = 1)
    {
        Response resp;
        size_t matched = 0;

        // TODO - Timeout?
        while (matched < expected) {
            Response[] responses = receiveResponses(conn, 1);

            while (!responses.empty) {
                auto found = responses.find!pred;

                // Enqueue older responses for later processing
                queue ~= responses[0 .. $ - found.length];

                responses = found;
                if (!responses.empty) {
                    resp = responses.front;
                    responses.popFront;
                    ++matched;
                }
            }
        }

        return resp;
    }

    /**
     * Process a single message
     */
    private void processMessage(Response resp)
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

        if (elements.length < 2)
        {
            reportBadResponse();
            return;
        }

        string type = element(0);

        switch (type)
        {
        case "message":
            if (elements.length != 3)
                reportBadResponse();
            else
            {
                string channel = element(1);
                const callback = (channel in callbacks);

                if (callback)
                {
                    string message = element(2);
                    (*callback)(channel, message);
                }
                else
                    stderr.writefln("No callback for message: %s", resp);
            }
            break;

        case "pmessage":
            if (elements.length != 4)
                reportBadResponse();
            else
            {
                string pattern = element(1);
                const callback = (pattern in pCallbacks);

                if (callback) {
                    string channel = element(2);
                    string message = element(3);

                    (*callback)(pattern, channel, message);
                }
                else
                    stderr.writefln("No callback for pattern message: %s", resp);
            }
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
        conn = new TcpSocket(new InternetAddress(host, port));
        conn.blocking = false;
    }

    /**
     * Create a new subscriber using an existing socket
     */
    this(TcpSocket conn)
    {
        this.conn = conn;
    }

    /**
     * Subscribe to a channel
     *
     * Returns the number of channels currently subscribed to
     */
    size_t subscribe(string channel, Callback callback)
    {
        auto cmd = "SUBSCRIBE " ~ channel;
        send(cmd);

        Response resp = queueExcept(r => r.isType!"subscribe");
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

        Response resp = queueExcept(r => r.isType!"psubscribe");
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

        Response resp = queueExcept(r => r.isType!"unsubscribe");
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
        auto cmd = "UNSUBSCRIBE";
        send(cmd);

        Response resp = queueExcept(r => r.isType!"unsubscribe", callbacks.length);
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

        Response resp = queueExcept(r => r.isType!"punsubscribe");
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
        auto cmd = "PUNSUBSCRIBE";
        send(cmd);

        Response resp = queueExcept(r => r.isType!"punsubscribe", pCallbacks.length);
        pCallbacks = null;

        return resp.values[2].to!int;
    }

    /**
     * Close the redis connection
     */
    Response quit()
    {
        auto cmd = "QUIT";
        send(cmd);

        Response resp = queueExcept(r => r.value == "OK");

        return resp;
    }

    /**
     * Send a PING command
     */
    Response ping(string argument = null)
    {
        auto cmd = "PING " ~ argument;

        send(cmd);
        Response resp = queueExcept(r => r.isType!"pong");

        return resp;
    }

    /**
     * Poll for queued messages on the redis server and call their callbacks
     */
    void processMessages()
    {
        queue ~= receiveResponses(conn, 0);

        foreach (arr; queue) {
            foreach (resp; arr) {
                processMessage(resp);
            }
        }

        queue.length = 0;
        queue.assumeSafeAppend();
    }
}
