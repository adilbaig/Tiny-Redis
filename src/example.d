import tinyredis,
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
    try{
        //The LASTSAVE command does not take any parameters and returns an int
        Response r = redis.send("LASTSAVE");
        assert(r.type == ResponseType.Integer);
        writeln(r.intval);
        
        //Here's how you get the value of the field 
        writeln(redis.send("SET name adil"));
        r = redis.send("GET name");
        writeln("My name is ", r.value);
        
        // You can build a command using the send(string[]) form
        auto nekeys = ["nonexistentkey", "nonexistentkey2", "nonexistentkey3"];
        foreach(k; nekeys)
            writeln(redis.send(["GET", k])); // ResponseType.Nil
        
        //And here's a redis set
        writeln(redis.send("SADD myset adil"));
        writeln(redis.send("SADD myset 350001939"));
        writeln(redis.send("SADD myset $"));
        writeln(redis.send("SMEMBERS myset"));
     
        //Redis Transactions
        writeln(redis.send("MULTI")); //OK
        writeln(redis.send("INCR foo")); //QUEUED
        writeln(redis.send("INCR bar")); //QUEUED
        writeln(redis.send("EXEC")); //[(Integer) 1, (Integer) 1] 
        
        //And finally this command will throw a RedisResponseException
        writeln(redis.send("AND THIS IS A COMMAND REDIS DOES NOT UNDERSTAND"));
    }catch(RedisResponseException e)
    {
        writeln("(error) ", e.msg);
    }
    
    //Lies, great lies, and benchmarks.
    uint reqs = 50_000;
    
    StopWatch sw;
    sw.reset();
    sw.start();
    for(uint i = 0; i < reqs; i++)
        redis.send("GET name");
    sw.stop();
    
    auto time = sw.peek().seconds;
    writeln(reqs/time, " reqs/sec for ", reqs, " requests in ", time, " seconds");
}