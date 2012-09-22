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
    const uint reqs = 50_000;
    
    StopWatch sw;
    sw.reset();
    sw.start();
    for(uint i = 0; i < reqs; i++)
        redis.send("GET name");
    sw.stop();
    
    auto time = sw.peek().msecs;
    writeln("INDIVIDUAL : ", reqs/time, "r/msec ", (reqs/time)*1000 , "r/sec ", reqs, " requests in ", time, " msecs");
    
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
    writeln("PIPELINED  : ", reqs/time, "r/msec ", (reqs/time)*1000 , "r/sec ", reqs, " requests in ", time, " msecs");
}