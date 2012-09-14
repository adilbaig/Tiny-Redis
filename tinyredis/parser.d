module tinyredis.parser;

private:
    import std.array     : split, replace;
    import std.stdio     : writeln;
    import std.conv      : to, text;
    
public : 

    const string CRLF = "\r\n";
    
    enum ResponseType : byte 
    {
        Status,
        Error,
        Integer,
        Bulk,
        MultiBulk,
        Nil
    }
    
    struct Response
    {
        ResponseType type;
        
        union{
            string value;
            int intval;
            Response[] values;
        }
        
        @property string toString()
        {
            switch(type)
            {
                case ResponseType.Nil : 
                    return "(Nil)";
                
                case ResponseType.Integer : 
                    return "(Integer) "  ~ to!(string)(intval);
                    
                case ResponseType.Status :
                case ResponseType.Bulk : 
                    return value;
                    
                case ResponseType.MultiBulk :
                    return text(values);
                    
                default:
                    return "";
            }
        }
    }

/* ---------- RESPONSE PARSING FUNCTIONS ----------- */

    /**
     * Encode a request to MultiBulk using any type that can be converted to a string
     *
     * encode("SADD", "myset", 1)
     * encode("SADD", "myset", 1.2)
     * encode("SADD", "myset", true)
     * encode("SADD", "myset", "Batman")
     * encode("SADD", "myset", object) //provided toString is implemented
     * encode("GET", "*") == encode("GET *")
     */
    string encode(T...)(string key, T args)
    {
        string request = key;
        
        static if(args.length > 0)
            foreach(a; args)
                request ~= " " ~ text(a);
        
        return toMultiBulk(request);
    }
    
    /**
     * Encode a request of a parametrized array
     *
     * encode("SREM", ["myset", "$3", "$4"]) == encode("SREM myset $3 $4")
     */
    string encode(T)(string key, T[] args)
    {
        string request = key;
        
        static if(is(typeof(T) == string))
            request ~= " " ~ args.join(" ");
        else
            foreach(a; args)
                request ~= " " ~ text(a);
                
        return toMultiBulk(request);
    }
    
    /**
     * Parse a response from Redis
     */
    Response[] parse(const(byte[]) response)
    in { assert(response.length > 0); }
//    out{ assert(response.length == pos); } //Can i do this?
    body
    {
        Response[] results;
        
        ulong pos = 0, p = 0;
        while(pos < response.length)
        {
            results ~= parseResponse(response[pos .. $], p);
            pos += p;
        }
        
        return results;
    }
    
    /* --------- BULK HANDLING FUNCTIONS ---------- */
    
    string toMultiBulk(string command)
    {
        string[] cmds = command.split();
        char[] res = "*" ~ to!(char[])(cmds.length) ~ CRLF;
        foreach(cmd; cmds)
            res ~= toBulk(cmd);
        
        return cast(string)res;
    }
    
    string toBulk(string str)
    {
        auto bytes = cast(byte[])str;
        return "$" ~ to!string(bytes.length) ~ CRLF ~ str ~ CRLF;
    }
    
    string escape(string str)
    {
         return replace(str,"\r\n","\\r\\n");
    }
    
    
    /* ----------- EXCEPTIONS ------------- */
    
    class ParseException : Exception {
        this(string msg) { super(msg); }
    }
    
    class RedisResponseException : Exception {
        this(string msg) { super(msg); }
    }
    
private :

    /**
     * Parse a byte stream into a response
     */
    Response parseResponse(const(byte[]) mb, ref ulong pos)
    {
        char type = mb[0];
        Response response;
        auto bytes = getData(mb[1 .. $]); //This could be an int value (:), a bulk byte length ($), a status message (+) or an error value (-)
        pos = 1 + bytes.length + 2;
        
        switch(type)
        {
             case '+' : 
                response = Response(ResponseType.Status, cast(string)bytes);
                return response;
                
            case '-' :
                throw new RedisResponseException(cast(string)bytes);
                
            case ':' :
                response.type = ResponseType.Integer;
                response.intval = to!int(cast(char[])bytes);
                return response;
            
            case '$' :
                int l = to!int(cast(char[])bytes);
                if(l == -1)
                {
                    response.type = ResponseType.Nil;
                    pos = 5;
                    return response;
                }
                
                response.type = ResponseType.Bulk;
                if(l > 0)
                    response.value = cast(string)mb[pos .. pos + l];
                
                pos += l + 2;
                return response;
            
            case '*' :
                response.type = ResponseType.MultiBulk;
                int items = to!int(cast(char[])bytes);
                
                ulong cp = 0;
                auto data = mb[pos .. $];
                for(uint i = 0; i < items; i++)
                {
                    response.values ~= parseResponse(data, cp);
                    data = data[cp .. $];
                    pos += cp;
                }
                
                return response;
            
            default :
                throw new Exception("Cannot understand response!");
        }
    }
    
    byte[] getData(const(byte[]) mb)
    {
        byte[] lgth;
        foreach(p, byte c; mb)
        {
            if(c == 13) //'\r' 
                break;
                
            lgth ~= c;
        }
        return lgth;
    }
    
    
unittest
{
    assert(toBulk("$2") == "$2\r\n$2\r\n");
    assert(toMultiBulk("GET *") == "*2\r\n$3\r\nGET\r\n$1\r\n*\r\n");
    
    Response[] r = parse(cast(byte[])"*4\r\n$3\r\nGET\r\n$1\r\n*\r\n:123\r\n+A Status Message\r\n");
    assert(r.length == 1);
    auto response = r[0];
    assert(response.type == ResponseType.MultiBulk);
    assert(response.values.length == 4);
    assert(response.values[0].value == "GET");
    assert(response.values[1].value == "*");
    assert(response.values[2].intval == 123);

    assert(response.values[3].value == "A Status Message");
    assert(encode("SREM", ["myset", "$3", "$4"]) == encode("SREM myset $3 $4"));
    assert(encode("SREM", "myset", "$3", "$4") == encode("SREM myset $3 $4"));
//    writeln(response);
} 