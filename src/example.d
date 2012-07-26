import tinyredis,
       std.stdio
    ;

/**
 * Make sure the redis server is running
 */
void main() 
{
    /**
     * If your redis server is not its standard host/port, adjust it here :
        auto redis = new Redis("address", port);
     */
    auto redis = new Redis();
    try{
        Response r = redis.send("LASTSAVE");
        assert(r.type == ResponseType.Integer);
        writeln(r.intval);
        
        r = redis.send("GET nonexistentkey");
        if(r.type == ResponseType.Nil)
            writeln("Non existent key not found!");
        
        writeln(redis.send("SET name adil"));
        writeln(redis.send("GET name"));
        
        writeln(redis.send("SADD myset adil"));
        writeln(redis.send("SADD myset 350001939"));
        writeln(redis.send("SADD myset $"));
        writeln(redis.send("SMEMBERS myset"));
    }catch(RedisResponseException e)
    {
        writeln("(error) ", e.msg);
    }
}
