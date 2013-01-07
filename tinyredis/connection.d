module tinyredis.connection;

private:
    import std.array;
    import std.stdio : writeln;
    import std.socket;
    import tinyredis.parser;
    

    /**
     * Class to communicate with Redis
     *
     * Creates a socket connection to Redis. Each call blocks until a response is received.
     * This class does not handle encoding. Use it to send raw MultiBulk encoded strings
     *
     */
    class RedisConnection
    {
        private :
            Socket conn;
        
        public :
        
            /**
            * Connect to a Redis server
            *
            * Example:
            *
            * ---
            * new RedisConnection("localhost", 6379);
            * ---
            */
            this(string host, ushort port)
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
             * Send a raw, redis encoded, command to the server and read the response(s).
             *
             * Examples:
             *
             * ---
             * Response[] responses = request(encode("GET", "*"));
             * for(r; responses)
             *      writeln(r);
             *
             * //Same as above, but with a Multibulk encoded string
             * Response[] responses = request("*2\r\n$3\r\nGET\r\n$1\r\n*\r\n");
             * for(r; responses)
             *      writeln(r);
             * 
             * //The following is an example of "pipelining" commands
             * request(encode("SET ctr 1") 
                        ~ encode("INCR ctr")
                        ~ encode("INCR ctr") 
                        ); //Same as Redis.pipeline(["SET ctr 1", "INCR ctr", "INCR ctr"])
             * ---
             */
            Response[] request(string command)
            in { assert(command.length > 0); }
            body 
            {
                debug { writeln("Request : '", escape(command) ~ "'"); }
                
                auto sent = conn.send(command);
                if (sent != (cast(byte[])command).length)
                    throw new ConnectionException("Error while sending request");
                    
                return receiveResponses();
            }            
            
        private :

            void receive(ref byte[] buffer)
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
            
            Response[] receiveResponses()
            {
                byte[] buffer;
                Response[] responses;
                Response*[] MultiBulks; //Stack of pointers to multibulks
                Response[]* stackPtr = &responses;
                
                while(true)
                {
                    receive(buffer);
                    
                    while(buffer.length > 0)
                    {
                        auto r = parseResponse(buffer);
                        if(r.type == ResponseType.Invalid)
                             break;
                       
                        *stackPtr ~= r;
                        if(r.type == ResponseType.MultiBulk)
                        {
                            auto mb = &((*stackPtr)[$-1]);
                            if(mb.count > 0)
                            {
                                MultiBulks ~= mb;
                                stackPtr = &((*mb).values);
                            }
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
        }
        
   /* -------- EXCEPTIONS ------------- */
    
    class ConnectionException : Exception {
        this(string msg) { super(msg); }
    }
