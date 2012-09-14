module tinyredis.redis;

private:
    import std.array     : join;
    import std.stdio     : writeln;
    import std.conv      : text;
    import std.socket;
    
public :

    import tinyredis.parser;
        
    class Redis
    {
        private :
            Socket conn;
        
        public :
            this(string host = "localhost", ushort port = 6379)
            {
                conn = new TcpSocket(new InternetAddress(host, port));
            }
            
            ~this()
            {
                if(conn.isAlive())
                    conn.close();
            }
            
            /**
             * Send a request using any type that can be converted to a string
             *
             * send("SADD", "myset", 1)
             * send("SADD", "myset", 1.2)
             * send("SADD", "myset", true)
             * send("SADD", "myset", "Batman")
             * send("SADD", "myset", object) //provided toString is implemented
             * send("GET", "*") == send("GET *")
             */
            Response send(T...)(string key, T args)
            {
                static if(args.length == 0)
                    return blockingRequest(conn, key);
                else
                {    
                    string query = key;
                    foreach(a; args)
                        query ~= " " ~ text(a);
                            
                    return blockingRequest(conn, query);
                }
            }
            
            /**
             * Send a request with a parameterized array. Ex:
             *
             * send("SREM", ["myset", "$3", "$4"]) == send("SREM myset $3 $4")
             */
            Response send(T)(string key, T[] args)
            {
                string query = key;
                
                static if(is(typeof(T) == string))
                    query ~= " " ~ args.join(" ");
                else
                    foreach(a; args)
                        query ~= " " ~ text(a);
                        
                return blockingRequest(conn, query);
            }
    }
    
private :

    Response blockingRequest(Socket conn, string request)
    in { assert(request.length > 0); }
    body {
        auto mb = toMultiBulk(request);
        debug { writeln("Request : ", "'"~request~"' (MultiBulk : '", escape(mb) ~ "')"); }
        
        auto sent = conn.send(mb);
        if (sent == 0)
            throw new ConnectionException("Error while sending request");
            
        byte[1024 * 4] buff;
        byte[] rez;
        long len;
        do{
            len = conn.receive(buff);
            rez ~= buff[0 .. len];
        }while(len > buff.length);
        
        debug { writeln("Response : ", "'" ~ escape(cast(string)rez) ~ "'"); }
        
        return parse(rez);
    }
    
   /* -------- EXCEPTIONS ------------- */
    
    class ConnectionException : Exception {
        this(string msg) { super(msg); }
    }


unittest
{
    auto redis = new Redis();
    auto response = redis.send("LASTSAVE");
    assert(response.type == ResponseType.Integer);
    
    redis.send("SET", "name", "adil");
    response = redis.send("GET name");
    assert(response.type == ResponseType.Bulk);
    assert(response.value == "adil");
    
    response = redis.send("GET nonexistentkey");
    assert(response.type == ResponseType.Nil);
    
    redis.send("DEL myset");
    redis.send("SADD myset adil");
    redis.send("SADD myset 350001939");
    redis.send("SADD myset $3");
    redis.send("SADD",["myset","$4"]);
    
    Response r = redis.send("SMEMBERS myset");
    assert(r.type == ResponseType.MultiBulk);
    assert(r.values.length == 4);
}