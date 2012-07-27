import tinyredis,
       std.stdio
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
        Response r = redis.send("LASTSAVE");
        assert(r.type == ResponseType.Integer);
        writeln(r.intval);
        
        r = redis.send("GET nonexistentkey");
        writeln(r); // ResponseType.Nil
        
        writeln(redis.send("SET name adil"));
        writeln(redis.send("GET name"));
        
        writeln(redis.send("SADD myset adil"));
        writeln(redis.send("SADD myset 350001939"));
        writeln(redis.send("SADD myset $"));
        writeln(redis.send("SMEMBERS myset"));
     
        writeln(redis.send("AND THIS IS A COMMAND REDIS DOES NOT UNDERSTAND"));
    }catch(RedisResponseException e)
    {
        writeln("(error) ", e.msg);
    }
}
