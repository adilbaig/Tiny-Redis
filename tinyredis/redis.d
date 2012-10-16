module tinyredis.redis;

private:
    import std.array;
    import std.stdio : writeln;
    import std.conv  : text;
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
            
            void close()
            {
                if(conn.isAlive())
                    conn.close();
            }
            
            ~this()
            {
                this.close();
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
                return this.sendRaw(encode(key, args))[0];
            }
            
            /**
             * Send a request with a parameterized array. Ex:
             *
             * send("SREM", ["myset", "$3", "$4"]) == send("SREM myset $3 $4")
             */
            Response send(T)(string key, T[] args)
            {
                return this.sendRaw(encode(key, args))[0];
            }
            
            /**
             * Send a series of commands as a pipeline
             *
             * pipeline(["SET ctr 1", "INCR ctr", "INCR ctr", "INCR ctr", "INCR ctr"])
             */
            Response[] pipeline(const string[] commands)
            {
                auto app = appender!string();
                foreach(c; commands)
                    app.put(encode(c));
                
                return this.sendRaw(app.data);
            }
            
            /**
             * Send a raw, redis encoded, command to the server and read the response
             *
             * sendRaw(encode("GET", "*"));
             * sendRaw("*2\r\n$3\r\nGET\r\n$1\r\n*\r\n"); 
             * sendRaw(encode("SET ctr 1") 
                        ~ encode("INCR ctr")
                        ~ encode("INCR ctr")
                        ~ encode("INCR ctr")
                        ~ encode("INCR ctr") 
                        ); //Pipelining. Same as pipeline(["SET ctr 1", "INCR ctr", "INCR ctr", "INCR ctr", "INCR ctr"])
             */
            Response[] sendRaw(string command)
            {
                sendCommand(conn, command);
                return receiveResponses(conn);
            }
    }
    
private :

    long sendCommand(Socket conn, string request)
    in { assert(request.length > 0); }
    body 
    {
        debug { writeln("Request : '", escape(request) ~ "'"); }
        
        auto sent = conn.send(request);
        if (sent != (cast(byte[])request).length)
            throw new ConnectionException("Error while sending request");
            
        return sent;
    }
    
    void receive(Socket conn, ref byte[] buffer)
    {
        byte[1024 * 16] buff;
        size_t len = conn.receive(buff);
        
        if(len == 0)
            throw new ConnectionException("Server closed the connection!");
        else if(len == Socket.ERROR)
            throw new ConnectionException("A socket error occured!");

        buffer ~= buff[0 .. len];
        
        debug { writeln("Response : ", "'" ~ escape(cast(string)buffer) ~ "'", " Length : ", len); }
    }
    
    Response[] receiveResponses(Socket conn)
    {
        byte[] buffer;
        Response[] responses;
        Response*[] MultiBulks; //Stack of pointers to multibulks
        Response[]* stackPtr = &responses;
        
        while(true)
        {
            receive(conn, buffer);
            
            while(buffer.length > 0)
            {
                auto r = parseResponse(buffer);
                if(r.type == ResponseType.Invalid)
                     break;
               
                *stackPtr ~= r;
                if(r.type == ResponseType.MultiBulk)
                {
                    auto mb = &((*stackPtr)[$-1]);
                    MultiBulks ~= mb;
                    stackPtr = &((*mb).values);
                }
                else
                    while(MultiBulks.length > 0)
                    {
                        auto mb = *(MultiBulks.back);
                        
                        if(mb.count == mb.values.length)
                        {
                            MultiBulks.popBack();
                            
                            if(MultiBulks.length > 0)
                                stackPtr = &((*MultiBulks.back).values);
                            else
                                stackPtr = &responses;
                        }
                        else
                            break;
                    }
            }
            
            if(buffer.length == 0
                && MultiBulks.length == 0) //Make sure all the multi bulks got their data
                break;
        }
        
        return responses;
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