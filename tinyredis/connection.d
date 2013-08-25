module tinyredis.connection;

private:
    import std.array;
    import std.stdio : writeln;
    import std.socket;
    import tinyredis.parser;
    
public:
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
                if(conn 
                    && conn.isAlive)
                    conn.close();
            }
            
            /**
             * Send a raw, redis encoded, command to the server and read the response(s).
             *
             * Examples:
             *
             * ---
             * request(encode("SMEMBERS", "myset"));
             * 
             * //The following is an example of "pipelining" commands
             * Response[] responses = request([encode("GET myname"), encode("GET hisname"), encode("GET hername")]);
             * foreach(r; responses)
             *      writeln(r);
             * ---
             */
            Response request(Request command)
            body 
            {
                Request[] r = [command];
                auto rez = request(r);
                return rez[0];
            }
            
            Response[] request(Request[] commands)
            in { assert(commands.length > 0); }
            body 
            {
                string command;
                foreach(c; commands)
                    command ~= c.toString();
                    
                debug { writeln("Request : '", escape(command) ~ "'"); }
                
                auto sent = conn.send(command);
                if (sent != (cast(byte[])command).length)
                    throw new ConnectionException("Error while sending request");
                    
                return receiveResponses(commands.length);
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
            
            Response[] receiveResponses(size_t minResponses = 0)
            {
                byte[] buffer;
                Response[] responses;
                Response*[] MultiBulks; //Stack of pointers to multibulks
                Response[]* stackPtr = &responses;
                
                while(true)
                {
                    receive(buffer);
                    
                    debug{ writeln("BUFFER : ", escape(cast(string)buffer)); } 
                    
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
                    {
                        debug {
                            if(minResponses > 1 && responses.length < minResponses)
                                writeln("WAITING FOR MORE RESPONSES ... ");
                        }
                            
                        if(responses.length < minResponses)
                            continue;
                            
                        break;
                    }
                        
                }
                
                return responses;
            }
        }
        
   /* -------- EXCEPTIONS ------------- */
    
    class ConnectionException : Exception {
        this(string msg) { super(msg); }
    }
