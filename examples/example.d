import tinyredis.redis,
       std.stdio
    ;

/**
 * Make sure the redis server is running
 */
void main()
{
    /**
     * If your redis server is not on its standard host/port, adjust the constructor
     */
    auto redis = new Redis();
    
    /*
     * In TinyRedis, any command can be executed as a string. 
       This is the most basic form of operation. TinyRedis supports all the 
       commands that the Redis server supports.
       In case there is an error in your command, an exception is raised.
    
       Each command returns a Response, which is queryable struct that contains
       the results from Redis 
     */
    redis.send("SET tinyredis Awesome");
    writeln("TinyRedis is ", redis.send("GET tinyredis")); //Printing the response will show you the output
    
    //And some more commands
    writeln("Open connections : ", redis.send("CLIENT LIST"));
    writeln("Server time : ", redis.send("TIME"));
    
    /*
      But there are better ways to use the driver. redis.send is a variable arguments 
      template, which means you can pass any type (convertible to a string) as a param.
    */
    int points = 32000;
    redis.send("SET", "points", points);
    redis.send("SET", "isCool", true);
    redis.send("SET", "centigrade", 32.5);
    
    
    /* 
      Here's how you can add multiple items to a Redis Set 
    */
    redis.send("SADD", "myset", "adil");
    redis.send("SADD", "myset", 350001939);
    redis.send("SADD", "myset", 1.2);
    redis.send("SADD", "myset", true);
    Response response = redis.send("SMEMBERS myset");
    writeln(response);

    /* 
      Or you can pipeline the queries 
    */
    Response[] buddies = redis.pipeline(["SADD buddies Batman", "SADD buddies Spiderman", "SADD buddies Hulk", "SMEMBERS buddies"]);
    writeln(buddies);

    /*
      Redis Transactions .. are pipelined!
    */
    Response[] responses = redis.transaction(["DEL ctr", "SET ctr 0", "INCR ctr", "INCR ctr"], true);
    writeln(responses);
    
    
    /*
      Now, lets look at the response.
    
      The Response struct will store the type in a "type" property
      and a corresponding value in a union.
      The three possible values in a union are :
       - intval : For values returned as Integers from Redis (not Integer strings)
       - value  : For string values
       - values[] : An array of Responses, for arrays
    */
    Response r = redis.send("LASTSAVE"); // This function returns an int
    if(r.type == ResponseType.Integer) //Check if the value is an int and print
        writeln(r.intval);
    if(r.isInt()) //Same as above
        writeln(r.intval);
    
    r = redis.send("GET tinyredis"); // This function returns a string
    if(r.type == ResponseType.Bulk) //Check the value and print
        writeln(r.value);
    if(r.isString()) //Same as above
        writeln(r.value);
        
    r = redis.send("SMEMBERS buddies"); // This function returns a string
    if(r.type == ResponseType.MultiBulk) //Check the value and print the array
        writeln(r.values);
    if(r.isArray()) //Same as above
        writeln(r.values);
        
                
    /*
        Since you already know what type of result to expect, you can 
        tell the send template to return the appropriate value directly
    */
    int s    = redis.send!(int)("LASTSAVE");
    string t = redis.send!(string)("GET tinyredis");
    bool b   = redis.send!(bool)("EXISTS tinyredis");
    
    // send can also cast the value from a string, if possible
    redis.send("SET amount 30");
    if(redis.send!(bool)("GET amount"))
        writeln("amount is greater than zero ", redis.send!(int)("GET amount"));
    
    
    /*
        For commands that return arrays, use the "values" property
        to fetch all items
    */
    r = redis.send("SMEMBERS buddies");
    foreach(k, v; r.values)
        writeln(k, ") ", v);
    foreach(k, v; r) //Response is loaded with opApply, you can iterate directly too.
        writeln(k, ") ", v);
    
    
    /*
        LUA Scripts
        Here is how you can do Raw EVAL. Note the \" at either ends of the script. That is required
        when using send
    */
    r = redis.send("EVAL", "\"return redis.call('set','lua','LUA')\"", 0);
    writeln(redis.send("GET lua"));
    r = redis.send("EVAL", "\"return {KEYS[1],KEYS[2],ARGV[1],ARGV[2]}\"", 2, "key1", "key2", "first", "second");
    writeln(r);
    
    /* 
        The eval template can take a standard string as Lua script, along with optional keys
        and arguments
    */
    r = redis.eval("return redis.call('set','lua','LUA_AGAIN')");
    writeln(redis.send("GET lua"));
    auto r1 = redis.eval("return {KEYS[1],KEYS[2],ARGV[1],ARGV[2]}", ["key1", "key2"], ["first", "second"]);
    writeln(r1); //Same as above
    
    try{
        //And finally this command will throw a RedisResponseException
        writeln(redis.send("AND_THIS_IS_A_COMMAND_REDIS_DOES_NOT UNDERSTAND"));
    }catch(RedisResponseException e)
    {
        writeln("(error) ", e.msg);
    }
}