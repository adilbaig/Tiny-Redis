module tinyredis.parser;

private:
    import std.array : split, replace, join;
    import std.stdio : writeln;
    import std.conv  : to, text;
    
public : 

    const string CRLF = "\r\n";
    
    enum ResponseType : byte 
    {
        Invalid,
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
        uint count; //Used for multibulk only
        
        union{
            string value;
            int intval;
            Response[] values;
        }
        
        @property @trusted string toString()
        {
            switch(type)
            {
                case ResponseType.Nil : 
                    return "(Nil)";
                
                case ResponseType.Error : 
                    return "(Err) " ~ value;
                
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

    /**
     * Parse a byte stream into a response. If successful remove that chunk from "mb" and return Response.
     * On failure returns a ResponseType.Invalid Response and does not modify "mb" 
     * 
     * @return Response
     */
    @trusted Response parseResponse(ref byte[] mb)
    {
        Response response;
        response.type = ResponseType.Invalid;
        
        if(mb.length < 4)
            return response;
            
        char type = mb[0];

        byte[] bytes;
        if(!getData(mb[1 .. $], bytes)) //This could be an int value (:), a bulk byte length ($), a status message (+) or an error value (-)
            return response;
            
        size_t tpos = 1 + bytes.length;
        
        if(tpos + 2 > mb.length)
            return response;
        else
            tpos += 2; //for "\r\n"
        
        switch(type)
        {
             case '+' : 
                response.type = ResponseType.Status;
                response.value = cast(string)bytes;
                break;
                
            case '-' :
                throw new RedisResponseException(cast(string)bytes);
                break;
                
            case ':' :
                response.type = ResponseType.Integer;
                response.intval = to!int(cast(char[])bytes);
                break;
                
            case '$' :
                int l = to!int(cast(char[])bytes);
                if(l == -1)
                {
                    response.type = ResponseType.Nil;
                    break;
                }
                
                if(l > 0)
                {
                    if(tpos + l >= mb.length) //We dont have enough data, break!
                        return response;
                    else
                    {
                        response.value = cast(string)mb[tpos .. tpos + l];
                        tpos += l;
                            
                        if(tpos + 2 > mb.length)
                            return response;
                        else
                            tpos += 2;
                    }
                }
                
                response.type = ResponseType.Bulk;
                break;
            
            case '*' :
                response.type = ResponseType.MultiBulk;
                response.count = to!int(cast(char[])bytes);
                break;
                
            default :
                return response;
        }
        
        mb = mb[tpos .. $];
        return response;
    }
    
    /* ---------- REQUEST PARSING FUNCTIONS ----------- */

    /**
     * Encodes a request to a MultiBulk using any type that can be converted to a string
     *
     * encode("SADD", "myset", 1)
     * encode("SADD", "myset", 1.2)
     * encode("SADD", "myset", true)
     * encode("SADD", "myset", "Batman")
     * encode("SADD", "myset", object) //provided toString is implemented
     * encode("GET", "*") == encode("GET *")
     */
    @trusted string encode(T...)(string key, T args)
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
     * encode("SREM", ["myset", "$3", "$4"])
     */
    @trusted string encode(T)(string key, T[] args)
    {
        string request = key;
        
        static if(is(typeof(args) == immutable(char)[]))
            request ~= " " ~ args;
        else
            foreach(a; args)
                request ~= " " ~ text(a);
                
        return toMultiBulk(request);
    }
    
    @trusted string toMultiBulk(string command)
    {
        string[] cmds = command.split();
        char[] res = "*" ~ to!(char[])(cmds.length) ~ CRLF;
        foreach(cmd; cmds)
            res ~= toBulk(cmd);
        
        return cast(string)res;
    }
    
    @trusted string toBulk(string str)
    {
        return "$" ~ to!string((cast(byte[])str).length) ~ CRLF ~ str ~ CRLF;
    }
    
    @trusted string escape(string str)
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
    @safe pure bool getData(const(byte[]) mb, ref byte[] data)
    {
        foreach(p, byte c; mb)
            if(c == 13) //'\r' 
                return true;
            else
                data ~= c;

        return false;
    }
    
    
unittest
{
    assert(toBulk("$2") == "$2\r\n$2\r\n");
    assert(toMultiBulk("GET *") == "*2\r\n$3\r\nGET\r\n$1\r\n*\r\n");
    
    byte[] stream = cast(byte[])"*4\r\n$3\r\nGET\r\n$1\r\n*\r\n:123\r\n+A Status Message\r\n";
    
    auto response = parseResponse(stream);
    assert(response.type == ResponseType.MultiBulk);
    assert(response.count == 4);
    assert(response.values.length == 0);
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Bulk);
    assert(response.value == "GET");
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Bulk);
    assert(response.value == "*");
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Integer);
    assert(response.intval == 123);
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Status);
    assert(response.value == "A Status Message");

    assert(stream.length == 0);
    assert(parseResponse(stream).type == ResponseType.Invalid);

    assert(encode("SREM", ["myset", "$3", "$4"]) == encode("SREM myset $3 $4"));
    assert(encode("SREM", "myset", "$3", "$4")   == encode("SREM myset $3 $4"));
    assert(encode("TTL", "myset")   == encode("TTL myset"));
    assert(encode("TTL", ["myset"]) == encode("TTL myset"));
//    writeln(response);
} 