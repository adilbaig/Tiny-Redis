import tinyredis,
       std.stdio
    ;

/**
 * This is simple redis console to demostrate Tiny Redis
 */
void main() 
{
    auto redis = new Redis();
    
    char[] buf; 
    
    write("redis > "); 
    while (stdin.readln(buf))
    {
        if(buf[0 .. $-1] == "exit") 
            return;
        
        if(buf.length > 0)
            try{
                writeln(redis.send(cast(string)buf));
            }catch(RedisResponseException e)
            {
                writeln("(error) ", e.msg);
            }
        
        write("redis > ");  
    }
}