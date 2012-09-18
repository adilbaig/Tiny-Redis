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
                return parse(blockingRequest(conn, encode(key, args)))[0];
            }
            
            /**
             * Send a request with a parameterized array. Ex:
             *
             * send("SREM", ["myset", "$3", "$4"]) == send("SREM myset $3 $4")
             */
            Response send(T)(string key, T[] args)
            {
                return parse(blockingRequest(conn, encode(key, args)))[0];
            }
            
            /**
             * Send a series of commands as a pipeline
             *
             * pipelined(["SET ctr 1", "INCR ctr", "INCR ctr", "INCR ctr", "INCR ctr"])
             */
            Response[] pipeline(const string[] commands)
            {
                string command;
                foreach(c; commands)
                    command ~= encode(c);
                    
                return parse(blockingRequest(conn, command));
            }
            
            /**
             * Send a raw, redis encoded command to the server
             */
            Response[] sendRaw(string command)
            {
                return parse(blockingRequest(conn, command));
            }
    }
    
private :

    byte[] blockingRequest(Socket conn, string request)
    in { assert(request.length > 0); }
    body 
    {
        debug { writeln("Request : '", escape(request) ~ "'"); }
        
        auto sent = conn.send(request);
        if (sent == 0)
            throw new ConnectionException("Error while sending request");
            
        byte[1024 * 4] buff;
        byte[] rez;
        long len;
        do{
            len = conn.receive(buff);
            rez ~= buff[0 .. len];
        }while(len == buff.length);
        
        debug { writeln("Response : ", "'" ~ escape(cast(string)rez) ~ "'", " Length : ", len); }
        
        return rez;
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
    redis.send("SADD", "myset", 1);
    redis.send("SADD", "myset", 1.2);
    redis.send("SADD", "myset", true);
    redis.send("SADD", "myset", "adil");
    redis.send("SADD", "myset", 350001939);
    redis.send("SADD",["myset","$4"]);
    auto r = redis.send("SMEMBERS myset");
    assert(r.type == ResponseType.MultiBulk);
    assert(r.values.length == 6);
    
    redis.send("DEL ctr");
    auto responses = redis.pipeline(["SET ctr 1", "INCR ctr", "INCR ctr", "INCR ctr", "INCR ctr"]);
//    writeln(responses);
    
    assert(responses.length == 5);
    assert(responses[0].type == ResponseType.Status);
    assert(responses[1].intval == 2);
    assert(responses[2].intval == 3);
    assert(responses[3].intval == 4);
    assert(responses[4].intval == 5);
}