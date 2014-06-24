import tinyredis.redis,
       std.stdio,
       std.datetime
    ;

/**
 * Make sure the redis server is running
 */
void main()
{
    /**
     * If your redis server is not on its standard host/port, adjust it here :
     */
    auto redis = new Redis("localhost", 6379);
    
    //Lies, great lies, and benchmarks.
    const uint reqs = 100_000;
    
    StopWatch sw;
    sw.reset();
    sw.start();
    for(uint i = 0; i < reqs; i++)
        redis.send("GET name");
    sw.stop();
    
    auto time = sw.peek().msecs;
    auto time_s = sw.peek().seconds;
    writeln("INDIVIDUAL : ", reqs/time, "r/ms  [~", (reqs/time_s), "r/s].  ", reqs, " requests in ", time, "ms");
    
    sw.reset();
    sw.start();
    
    auto str = encode("GET name").toString();
    for(uint i = 0; i < reqs; i++)
        redis.sendRaw(str);
    sw.stop();
    
    time = sw.peek().msecs;
    time_s = sw.peek().seconds;
    writeln("INDIVIDUAL (RAW): ", reqs/time, "r/ms  [~", (reqs/time_s), "r/s].  ", reqs, " requests in ", time, "ms");
    
    sw.reset();
    sw.start();
    
    //Now test with pipelining
    const uint batchSize = 70;
    for(uint j = 0; j < reqs; j += batchSize)
    {
        string[batchSize] commands = new string[batchSize];
        
        for(uint i = 0; i < batchSize; i++)
            commands[i] = "GET name";
        
        auto response = redis.pipeline(commands);
    }
    
    sw.stop();
    
    time = sw.peek().msecs;
    time_s = sw.peek().seconds;
    writeln("PIPELINED  : ", reqs/time, "r/ms [~", (reqs/time_s), "r/s]. ", reqs, " requests in ", time, "ms");
}