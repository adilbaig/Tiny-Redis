module tinyredis.request;

public import tinyredis.encoder;

public :

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
    