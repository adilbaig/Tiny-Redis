module tinyredis.connection;

public:
    import std.socket : TcpSocket;
	    
private:
    import std.array : appender, back, popBack;
    import tinyredis.parser;

debug {
	import std.stdio : writeln;
}    

public:

	/**
     * Sends a pre-encoded string
     *
     * Params:
     *   conn     = Connection to redis server.
     *   encoded_cmd = The command to be sent.
     *
     * Throws: $(D ConnectionException) if sending fails.
     */
	Response requestRaw(TcpSocket conn, string encoded_cmd)
    {
        debug { writeln("Request : '", escape(encoded_cmd) ~ "'"); }
        
        auto sent = conn.send(encoded_cmd);
        if (sent != (cast(byte[])encoded_cmd).length)
            throw new ConnectionException("Error while sending request");
            
        return receiveResponses(conn, 1)[0];
    }

	Response request(TcpSocket conn, Request command)
    {
		string cmd = command.toString;
        debug { writeln("Request : '", escape(cmd) ~ "'"); }
        
        auto sent = conn.send(cmd);
        if (sent != (cast(byte[])cmd).length)
            throw new ConnectionException("Error while sending request");
            
        return receiveResponses(conn, 1)[0];
    }
    
    Response[] request(TcpSocket conn, Request[] commands)
    in { assert(commands.length > 0); }
    body 
    {
    	auto appender = appender!string();
        foreach(c; commands)
            appender ~= c.toString();
            
        debug { writeln("Request : '", escape(appender.data) ~ "'"); }
        
        auto sent = conn.send(appender.data);
        if (sent != (cast(byte[])appender.data).length)
            throw new ConnectionException("Error while sending request");
            
        return receiveResponses(conn, commands.length);
    }

private :
    
    void receive(TcpSocket conn, ref byte[] buffer)
    {
        byte[1024 * 16] buff;
        size_t len = conn.receive(buff);
        
        if(len == 0)
            throw new ConnectionException("Server closed the connection!");
        else if(len == TcpSocket.ERROR)
            throw new ConnectionException("A socket error occurred!");

        buffer ~= buff[0 .. len];
        debug { writeln("Response : ", "'" ~ escape(cast(string)buff) ~ "'", " Length : ", len); }
    }
    
    Response[] receiveResponses(TcpSocket conn, size_t minResponses = 0)
    {
        byte[] buffer;
        Response[] responses;
        Response*[] MultiBulks; //Stack of pointers to multibulks
        Response[]* stackPtr = &responses;
        
        while(true)
        {
            receive(conn, buffer);
            
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
            
            if(buffer.length == 0 && MultiBulks.length == 0) //Make sure all the multi bulks got their data
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
    
    
   /* -------- EXCEPTIONS ------------- */
    
    class ConnectionException : Exception {
        this(string msg) { super(msg); }
    }
