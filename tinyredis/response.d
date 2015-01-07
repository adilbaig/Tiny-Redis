module tinyredis.response;

/**
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */

private:
    import std.array : split, replace, join;
    import std.string : strip, format;
    import std.stdio : writeln;
    import std.algorithm : find;
    import std.conv  : to, text, ConvOverflowException;
    import std.conv;
    import std.traits;
    
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
        
        private int curr;
        
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
        
        /*
         * Response is a BidirectionalRange
         */
        @property bool empty()
        {
            if(!isArray()) {
                return true;
            }
            
            return (curr == values.length);
        }
        
        @property auto front()
        {
            return values[curr];
        }
        
        @property void popFront()
        {
            curr++;
        }
        
        @property auto back()
        {
            return values[values.length - 1];
        }
    
        @property void popBack()
        {
            curr--;
        }
        
        // Response is a ForwardRange
        @property auto save()
        {
            // Returning a copy of this struct object
            return this;
        }
    
        /**
         * Support foreach(k, v; response)
         */
        int opApply(int delegate(size_t, Response) dg)
        {
            if(!isArray()) {
                return 1;
            }
            
            foreach(k, v; values) {
                dg(k, v);
            }
            
            return 0;
        }
        
        /**
         * Support foreach_reverse(k, v; response)
         */
        int opApplyReverse(int delegate(size_t, Response) dg)
        {
            if(!isArray()) {
                return 1;
            }
            
            foreach_reverse(k, v; values) {
                dg(k, v);
            }
            
            return 0;
        }
        
        /**
         * Support foreach(v; response)
         */
        int opApply(int delegate(Response) dg)
        {
            if(!isArray()) {
                return 1;
            }
            
            foreach(v; values) {
                dg(v);
            }
            
            return 0;
        }
        
        /**
         * Support foreach_reverse(v; response)
         */
        int opApplyReverse(int delegate(Response) dg)
        {
            if(!isArray()) {
                return 1;
            }
            
            foreach_reverse(v; values) {
                dg(v);
            }
            
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
                || is(T == string)
		|| is(ubyte[]))
        {
            static if(is(T == bool))
                return toBool();
            else static if(is(T == byte) || is(T == short) || is(T == int) || is(T == long))
                return toInt!(T)();
            else static if(is(T == string))
                return toString();
	    else static if(is(ubyte[]))
	        return cast(ubyte[])(values);
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
    
    /* ----------- EXCEPTIONS ------------- */
    
    class RedisCastException : Exception {
        this(string msg) { super(msg); }
    }

