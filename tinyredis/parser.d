module tinyredis.parser;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

private:
    import std.conv  : to;
    import std.range : isInputRange, isForwardRange, isBidirectionalRange, retro;
    
public : 

	import tinyredis.response;

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
    
    
    
    /* ----------- EXCEPTIONS ------------- */
    
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
    foreach(k, v; response)
        assert(false, "opApply is broken");
    foreach(v; response)
        assert(false, "opApply is broken");
    
    stream = cast(byte[])"$2\r\n$2\r\n";
    response = parseResponse(stream);
    foreach(k, v; response)
        assert(false, "opApply is broken");
    foreach(v; response)
        assert(false, "opApply is broken");
        
    stream = cast(byte[])":1000\r\n";
    response = parseResponse(stream);
    foreach(k, v; response)
        assert(false, "opApply is broken");
    foreach(v; response)
        assert(false, "opApply is broken");
        
    //Testing opApplyReverse
    stream = cast(byte[])"*0\r\n";
    response = parseResponse(stream);
    foreach_reverse(k, v; response)
        assert(false, "opApplyReverse is broken");
    foreach_reverse(v; response)
        assert(false, "opApplyReverse is broken");
   
        
    //Testing ranges for Response
    assert(isInputRange!Response);
    assert(isForwardRange!Response);
    assert(isBidirectionalRange!Response);
} 