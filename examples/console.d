import tinyredis.redis,
       std.stdio
    ;

/**
 * This is a simple console to demonstrate Tiny Redis
 */
void main() 
{
    auto redis = new Redis();
    
    char[] buf; 
    
    write("redis > "); 
    while (stdin.readln(buf))
    {
        string cmd = cast(string)buf[0 .. $-1];
        
        if(cmd == "exit") 
            return;
        
        if(cmd.length > 0)
            try{
                Response resp = redis.send(cmd);
                if (resp.isString) {
                    writeln('"', resp.toDiagnosticString(), '"');
                } else {
                    writeln(resp.toDiagnosticString());
                }
            }
            catch(RedisResponseException e) {
                writeln("(error) ", e.msg);
            }
            catch(ConnectionException e) {
                writeln("(error) ", e.msg);
            }
        
        write("redis > ");  
    }
}