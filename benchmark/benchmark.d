import tinyredis.redis,
       tinyredis.subscriber,
       tinyredis.encoder,
       std.stdio,
       std.getopt,
       std.datetime,
       std.array,
       std.math
    ;

/**
 This benchmarking program is inspired by redis-benchmark. 
 Although the purpose here is to test the TinyRedis driver.
 
 Authors: Adil Baig, adil.baig@aidezigns.com
*/

void usage(string program)
{
	writeln("Usage : ", program, " [-h <host>] [-p <port>] [-n <requests>]");
	writeln("
  -h | --host <hostname>      Server hostname (default 127.0.0.1)
  -p | --port <port>          Server port (default 6379)
  -n | --requests <requests>  Number of requests (default 100,000)
  -P | --pipeline <numreq>    Pipeline <numreq> requests. (default 1) (no pipeline).

  This script benchmarks the TinyRedis driver with a Redis server.
  WARNING : The script writes some data to the Redis server as part of the benchmark. Best not to run this on a production server.
	");
}

void timeCommand(Redis redis, string command, ref StopWatch sw, const uint reqs, const uint pipeline)
{
    sw.reset();
    sw.start();
    
    auto e = encode(command);
    if(pipeline > 1) {
    	e = std.array.replicate(e, pipeline);
    }
    
    for(uint i = 0; i < reqs/pipeline; i++)
        redis.sendRaw(e);
    
    sw.stop();
    
    writefln("%d requests completed in %.3f seconds", reqs, sw.peek().msecs()/1000.0);
    writefln("%d requests per second", cast(uint)std.math.round(reqs/(sw.peek().msecs()/1000.0)));
    writeln("");
}

void timePubSub(Redis redis, Subscriber subscriber, string command, ref StopWatch sw, const uint reqs, const uint pipeline)
{
    sw.reset();
    sw.start();

    auto e = encode(command);
    if(pipeline > 1) {
    	e = std.array.replicate(e, pipeline);
    }

    for(uint i = 0; i < reqs/pipeline; i++)
    {
        redis.sendRaw(e);
        subscriber.processMessages();
    }

    sw.stop();

    writefln("%d messages processed in %.3f seconds", reqs, sw.peek().msecs()/1000.0);
    writefln("%d messages per second", cast(uint)std.math.round(reqs/(sw.peek().msecs()/1000.0)));
    writeln("");
}

/**
 * Make sure the redis server is running
 */
int main(string[] args)
{
	string host = "127.0.0.1"; 
	ushort port = 6379;
	uint reqs = 100_000;
	bool help = false;
	uint pipeline = 1;
	
	getopt(
	    args,
	    "host|h",  &host,
	    "port|p",  &port,
	    "requests|n",  &reqs,
	    "pipeline|P",  &pipeline,
	    "help",  &help
	    );
    
    if(help || pipeline < 1) {
		usage(args[0]);
		return 1;
	}

    auto redis = new Redis(host, port);
    
    //Lies, great lies, and benchmarks.
    StopWatch sw;
    
    redis.send("SET trbck:get 12");
    
    writeln("====== GET ======");
    timeCommand(redis, "GET trbck:get", sw, reqs, pipeline);
    
    writeln("====== SET ======");
    timeCommand(redis, "SET trbck:get 12", sw, reqs, pipeline);

    auto subscriber = new Subscriber();
    ulong messages = 0;
    ulong pmessages = 0;
    subscriber.subscribe("my_channel", (channel, message) { ++messages; });
    subscriber.psubscribe("my_pattern*", (pattern, channel, message) { ++pmessages; });

    writeln("====== SUBSCRIBE ======");
    timePubSub(redis, subscriber, "PUBLISH my_channel my_message", sw, reqs, pipeline);
    if (messages != reqs)
        writefln("WARNING: Expected %s messages, processed %s messages\n", reqs, messages);

    writeln("====== PSUBSCRIBE ======");
    timePubSub(redis, subscriber, "PUBLISH my_patternX my_message", sw, reqs, pipeline);
    if (pmessages != reqs)
        writefln("WARNING: Expected %s messages, processed %s messages\n", reqs, pmessages);

    return 0;
}
