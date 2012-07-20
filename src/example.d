import tinyredis,
       std.stdio
    ;

void main() 
{
    auto redis = new Redis();
    writeln(redis.send("GET *"));
    writeln(redis.send("SADD myset adil"));
    writeln(redis.send("SADD myset 350001939"));
    writeln(redis.send("SADD myset $"));
    writeln(redis.send("SMEMBERS myset"));
}
