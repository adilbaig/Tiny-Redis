module tinyredis.parser;

private:
    import std.array : split, replace, join;
    import std.string : strip, format;
    import std.stdio : writeln;
    import std.algorithm : find;
    import std.conv  : to, text, ConvOverflowException;
    import std.traits;
    
public : 

	import tinyredis.encoder;
	
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
    
    /**
     * The Response struct represents returned data from Redis. 
     *
     * Stores values true to form. Allows user code to query, cast, iterate, print, and log strings, ints, errors and all other return types.
     * 
     * The role of the Response struct is to make it simple, yet accurate to retrieve returned values from Redis. To aid this
     * it implements D op* functions as well as little helper methods that simplify user facing code. 
     */
    struct Response
    {
        ResponseType type;
        int count; //Used for multibulk only. -1 is a valid multibulk. Indicates nil
        
        union{
            string value;
            long intval;
            Response[] values;
        }
        
        bool isString()
        {
            return (type == ResponseType.Bulk);
        }
        
        bool isInt()
        {
            return (type == ResponseType.Integer);
        }
        
        bool isArray()
        {
            return (type == ResponseType.MultiBulk);
        }
        
        bool isError()
        {
            return (type == ResponseType.Error);
        }
        
        bool isNil()
        {
            return (type == ResponseType.Nil); 
        }
        
        bool isStatus()
        {
            return (type == ResponseType.Status);
        }
        
        bool isValid()
        {
            return (type != ResponseType.Invalid);
        }
        
        int opApply(int delegate(ulong k, Response value) dg)
        {
            if(!isArray())
                return 1;
                
            foreach(k, v ; values)
                dg(k, values[k]);
            
            return 0;
        }
        
        /**
         * Allows casting a Response to an integral, bool or string
         */
        T opCast(T)()
        if(is(T == bool)
                || is(T == byte)
                || is(T == short)
                || is(T == int)
                || is(T == long)
                || is(T == string))
        {
            static if(is(T == bool))
                return toBool();
            else static if(is(T == byte) || is(T == short) || is(T == int) || is(T == long))
                return toInt!(T)();
            else static if(is(T == string))
                return toString();
        }
        
        /**
         * Attempts to check for truthiness of a Response.
         * 
         * Returns false on failure.
         */
        @property @trusted bool toBool()
        {
            switch(type)
            {
                case ResponseType.Integer : 
                    return (intval > 0);
                    
                case ResponseType.Status :
                    return (value == "OK");
                    
                case ResponseType.Bulk : 
                    return (value.length > 0);
                    
                case ResponseType.MultiBulk :
                    return (values.length > 0);
                    
                default:
                    return false;
            }
        }
        
        /**
         * Converts a Response to an integral (byte to long)
         *
         * Only works with ResponseType.Integer and ResponseType.Bulk
         *
         * Throws : ConvOverflowException, RedisCastException
         */
        @property @trusted T toInt(T = int)()
        if(is(T == byte) || is(T == short) || is(T == int) || is(T == long))
        {
            switch(type)
            {
                case ResponseType.Integer : 
                    if(intval <= T.max)
                        return cast(T)intval;
                    else
                        throw new ConvOverflowException("Cannot convert " ~ to!string(intval) ~ " to " ~ to!(string)(typeid(T)));
//                    break;
                    
                case ResponseType.Bulk : 
                    try{
                        return to!(T)(value);
                    }catch(ConvOverflowException e)
                    {
                        e.msg = "Cannot convert " ~ value ~ " to " ~ to!(string)(typeid(T));
                        throw e;
                    }
//                    break;
                
                default:
                    throw new RedisCastException("Cannot cast " ~ type ~ " to " ~ to!(string)(typeid(T)));
            }
        }
        
        /**
         * Returns the value of this Response as a string
         */
        @property @trusted string toString()
        {
            switch(type)
            {
                case ResponseType.Integer : 
                    return to!(string)(intval);
                    
                case ResponseType.Error :
                case ResponseType.Status :
                case ResponseType.Bulk : 
                    return value;
                    
                case ResponseType.MultiBulk :
                    return text(values);
                    
                default:
                    return "";
            }
        }
        
        /**
         * Returns the value of this Response as a string, along with type information
         */
        @property @trusted string toDiagnosticString()
        {
            final switch(type)
            {
                case ResponseType.Nil : 
                    return "(Nil)";
                
                case ResponseType.Error : 
                    return "(Err) " ~ value;
                
                case ResponseType.Integer : 
                    return "(Integer) " ~ to!(string)(intval);
                    
                case ResponseType.Status :
                    return "(Status) " ~ value;
                    
                case ResponseType.Bulk : 
                    return value;
                    
                case ResponseType.MultiBulk :
                    string[] t;
                    
                    foreach(v; values)
                        t ~= v.toDiagnosticString();
                        
                    return text(t);
                    
                case ResponseType.Invalid :
                    return "(Invalid)";
            }
        }
    }

    /**
     * Parse a byte stream into a Response struct. 
     *
     * The parser works to identify a minimum complete Response. If successful, it removes that chunk from "mb" and returns a Response struct.
     * On failure it returns a ResponseType.Invalid Response and leaves "mb" untouched. 
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
//                break;
                
            case ':' :
                response.type = ResponseType.Integer;
                response.intval = to!long(cast(char[])bytes);
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
            	int l = to!int(cast(char[])bytes);
                if(l == -1)
                {
                    response.type = ResponseType.Nil;
                    break;
                }
                
                response.type = ResponseType.MultiBulk;
                response.count = l;
                 
                break;
                
            default :
                return response;
        }
        
        mb = mb[tpos .. $];
        return response;
    }
    
    
    /* ---------- REQUEST PARSING FUNCTIONS ----------- */

    /**
     Represents a Request to be sent to the server
    */
    struct Request
    {
        string[] args; 
        
        @property void add(T)(T arg)
        {
            static if(isArray!(typeof(arg)) && !is(typeof(arg) == immutable(char)[])) {
                foreach(b; arg)
                    add(b);
            }
            else 
                args ~= text(arg);
        }
    
        @property @trusted string toString()
        {
            return argsToMultiBulk(args);
        }
        
        alias toMultiBulk toString;
    }
    
    private string[] stripAndChop(string cmd)
    {
        /*
         Sometimes a command is passed as a full string. Ex: command = "GET *s";
         This function breaks it down to its args
        */ 
        
        auto command = strip(cmd);
        
        string[] cmds;
        char[] buffer;
        
        //Loop through each char ..
        uint i = 0;
        while(i < command.length)
        {
            auto c = command[i++];
            
            // ..if the char is a ", accumalate all characters until another " is found.
            if(c == '"')
            {
                while(i < command.length)
                {
                    auto c1 = command[i++];
                    if(c1 == '"')
                        break;
                    buffer ~= c1;
                }
            } // if a space is found, cat the buffer to cmds ..
            else if(c == ' ')
            {
                cmds ~= cast(string)buffer;
                buffer.length = 0;
            }
            else // .. else cat everything else
                buffer ~= c;
        }
        
        cmds ~= cast(string)buffer;
        return cmds;
    }
    
    /**
     * Encodes a Redis command to a Request struct using any type that can be converted to a string
     *
     * Examples:
     * ---
     * encode("SADD", "myset", 1)
     * encode("SADD", "myset", 1.2)
     * encode("SADD", "myset", true)
     * encode("SADD", "myset", "Batman")
     * encode("DEL", ["key1", "key2"])
     * encode("SADD", "numbers", [1,2,3])
     * encode("SADD", "myset", object) //provided toString is implemented
     * encode("GET", "*") == encode("GET *") == encode("GET", ["*"])
     * ---
     */
    @trusted Request encode(T...)(string key, T args)
    {
        Request r;
        
        foreach(piece; stripAndChop(key))
            r.add = piece;
            
        foreach(a; args)
            r.add = a;
        
        return r;
    }
    
    /* ----------- EXCEPTIONS ------------- */
    
    class ParseException : Exception {
        this(string msg) { super(msg); }
    }
    
    class RedisResponseException : Exception {
        this(string msg) { super(msg); }
    }
    
    class RedisCastException : Exception {
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
    assert(encode("GET *2").toString() == "*2\r\n$3\r\nGET\r\n$2\r\n*2\r\n");
    assert(encode("TTL myset").toString() == "*2\r\n$3\r\nTTL\r\n$5\r\nmyset\r\n");
    assert(encode("TTL", "myset").toString() == "*2\r\n$3\r\nTTL\r\n$5\r\nmyset\r\n");
    
    auto lua = "return redis.call('set','foo','bar')";
    assert(encode("EVAL \"" ~ lua ~ "\" 0").toString() == "*3\r\n$4\r\nEVAL\r\n$"~to!(string)(lua.length)~"\r\n"~lua~"\r\n$1\r\n0\r\n");
    assert(encode("\"" ~ lua ~ "\" \"" ~ lua ~ "\" ").toString() == "*2\r\n$"~to!(string)(lua.length)~"\r\n"~lua~"\r\n$"~to!(string)(lua.length)~"\r\n"~lua~"\r\n");
    assert(encode("eval \"" ~ lua ~ "\" " ~ "0") == encode("eval", lua, 0));
    
    //Testing encode
    assert(encode("SREM", ["myset", "$3", "$4"]).toString() == encode("SREM myset $3 $4").toString());
    assert(encode("SREM", "myset", "$3", "$4").toString()   == encode("SREM myset $3 $4").toString());
    assert(encode("SADD", "numbers", [1,2,3]).toString()    == encode("SADD numbers 1 2 3").toString());
    assert(encode("TTL", "myset").toString() == encode("TTL myset").toString());
    assert(encode("TTL", "myset").toString() == encode("TTL", ["myset"]).toString());
    
    //Test Nil bulk
    byte[] stream = cast(byte[])"$-1\r\n";
    auto response = parseResponse(stream);
    assert(response.toString == "");
    assert(response.toBool == false);
    assert(cast(bool)response == false);
    try{
        cast(int)response;
        assert(false);
    }catch(RedisCastException e)
    {
        assert(true);
    }
    
    //Test Nil multibulk
    stream = cast(byte[])"*-1\r\n";
    response = parseResponse(stream);
    assert(response.toString == "");
    assert(response.toBool == false);
    assert(cast(bool)response == false);
    try{
        cast(int)response;
        assert(false);
    }catch(RedisCastException e)
    {
        assert(true);
    }
    
    stream = cast(byte[])"*4\r\n$3\r\nGET\r\n$1\r\n*\r\n:123\r\n+A Status Message\r\n";
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.MultiBulk);
    assert(response.count == 4);
    assert(response.values.length == 0);
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Bulk);
    assert(response.value == "GET");
    assert(cast(string)response == "GET");
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Bulk);
    assert(response.value == "*");
    assert(cast(bool)response == true);
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Integer);
    assert(response.intval == 123);
    assert(cast(string)response == "123");
    assert(cast(int)response == 123);
    
    response = parseResponse(stream);
    assert(response.type == ResponseType.Status);
    assert(response.value == "A Status Message");
    assert(cast(string)response == "A Status Message");
    try{
        cast(int)response;
    }catch(RedisCastException e)
    {
        //Exception caught
    }

    //Stream should have been used up, verify
    assert(stream.length == 0);
    assert(parseResponse(stream).type == ResponseType.Invalid);

    //Long overflow checking
    stream = cast(byte[])":9223372036854775808\r\n";
    try{
        parseResponse(stream);
        assert(false, "Tried to convert long.max+1 to long");
    }
    catch(ConvOverflowException e){}
    
    Response r = {type : ResponseType.Bulk, value : "9223372036854775807"};
    try{
        r.toInt(); //Default int
        assert(false, "Tried to convert long.max to int");
    }
    catch(ConvOverflowException e)
    {
        //Ok, exception thrown as expected
    }
    
    r.value = "127";
    assert(r.toInt!byte() == 127); 
    assert(r.toInt!short() == 127); 
    assert(r.toInt!int() == 127); 
    assert(r.toInt!long() == 127); 
    
    stream = cast(byte[])"*0\r\n";
    response = parseResponse(stream);
    assert(response.count == 0);
    assert(response.values.length == 0);
    assert(response.values == []);
    assert(response.toString == "[]");
    assert(response.toBool == false);
    assert(cast(bool)response == false);
    try{
        cast(int)response;
    }catch(RedisCastException e)
    {
        assert(true);
    }
    
    //Testing opApply
    stream = cast(byte[])"*0\r\n";
    response = parseResponse(stream);
    foreach(k,v; response)
        assert(false, "opApply is broken");
    
    stream = cast(byte[])"$2\r\n$2\r\n";
    response = parseResponse(stream);
    foreach(k,v; response)
        assert(false, "opApply is broken");
        
    stream = cast(byte[])":1000\r\n";
    response = parseResponse(stream);
    foreach(k,v; response)
        assert(false, "opApply is broken");
} 