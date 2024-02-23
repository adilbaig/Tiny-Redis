/**
 * Contain functions and type related to connections and their lifetime.
 *
 * Authors: Adil Baig, adil.baig@aidezigns.com
 */
module tinyredis.connection;

import std.exception : basicExceptionCtors;
import std.format;
import std.range;
import std.socket;
version(Windows) import core.sys.windows.winsock2: EWOULDBLOCK;
version(Have_openssl) {
	import deimos.openssl.err;
	import deimos.openssl.ssl;
}

import tinyredis.response;

debug(tinyredis) {
	import std.stdio : writeln;
	import tinyredis.encoder : escape;
}

interface Transport
{
	void blocking(bool b);
	bool blocking();
	void send(string buffer);
	size_t receive(char[] buffer);
	void close() @nogc nothrow;
}

class TcpTransport : Transport
{
	private TcpSocket socket;

	public this(InternetAddress address)
	{
		socket = new TcpSocket(address);
	}

	override void blocking(bool b)
	{
		socket.blocking = b;
	}

	override bool blocking()
	{
		return socket.blocking;
	}

	override void send(string buffer)
	{
		while (!buffer.empty)
		{
			size_t ret = socket.send(cast(const(ubyte)[]) buffer);

			if (ret <= 0)
			{
				throw new ConnectionException(format!"Error while sending request: %s"(ret));
			}
			buffer = buffer[ret .. $];
		}
	}

	override size_t receive(char[] buffer)
	{
		import core.stdc.errno;

		size_t len = socket.receive(cast(ubyte[]) buffer);

		if (blocking)
		{
			if (len == 0)
				throw new ConnectionException("Server closed the connection!");
			if (len == TcpSocket.ERROR)
				throw new ConnectionException("A socket error occurred!");
		}
		else if (len == TcpSocket.ERROR)
		{
			if (errno != EWOULDBLOCK)
				throw new ConnectionException(format!"A socket error occurred! errno: %s"(errno));
			len = 0;
			errno = 0;
		}
		return len;
	}

	override void close() @nogc nothrow
	{
		socket.close();
	}
}

version (Have_openssl)
{
	shared static this()
	{
		OpenSSL_add_all_algorithms;
		SSL_library_init;
		SSL_load_error_strings;
		ERR_load_SSL_strings;
	}

	class TlsTransport : Transport
	{
		private SSL_CTX* sslContext;

		private BIO* bio;

		private X509* certificate;

		private X509* redisCertificateAuthority;

		private EVP_PKEY* privateKey;

		public this(string host, ushort port, const(ubyte)[] certificateData, const(ubyte)[] privateKeyData,
			const(ubyte)[] caData)
		{
			import std.string : toStringz;

			this.sslContext = SSL_CTX_new(SSLv23_client_method);

			// we don't care about manual retries
			SSL_CTX_set_mode(this.sslContext, SSL_MODE_AUTO_RETRY);

			// Create temporary bios for the cert and pk
			auto certificateBio = BIO_new_mem_buf(cast(void*) certificateData.ptr, cast(int) certificateData.length);
			assert(certificateBio !is null);
			this.certificate = PEM_read_bio_X509(certificateBio, null, null, null);
			BIO_free(certificateBio);

			auto privateKeyBio = BIO_new_mem_buf(cast(void*) privateKeyData.ptr, cast(int) privateKeyData.length);
			assert(privateKeyBio !is null);
			this.privateKey = PEM_read_bio_PrivateKey(privateKeyBio, null, null, null);
			BIO_free(privateKeyBio);

			if (!caData.empty)
			{
				auto caBIO = BIO_new_mem_buf(cast(void*) caData.ptr, cast(int) caData.length);
				assert(caBIO !is null);
				this.redisCertificateAuthority = PEM_read_bio_X509(caBIO, null, null, null);
				BIO_free(caBIO);
			}
			else
			{
				this.redisCertificateAuthority = null;
				SSL_CTX_set_default_verify_paths(this.sslContext)
					.checkOpensslError!"could not set default certificate store";
			}

			auto store = SSL_CTX_get_cert_store(this.sslContext);

			SSL_CTX_use_certificate(this.sslContext, this.certificate).checkOpensslError!"could not set certificate";
			SSL_CTX_use_PrivateKey(this.sslContext, this.privateKey).checkOpensslError!"could not set private key";
			X509_STORE_add_cert(store, this.redisCertificateAuthority).checkOpensslError!"could not add Redis CA cert";

			this.bio = BIO_new_ssl_connect(this.sslContext);

			const addressString = format!"%s:%s"(host, port);

			BIO_set_conn_hostname(this.bio, cast(char*) addressString.toStringz);
			BIO_do_connect(this.bio).checkOpensslError!"could not connect to %s:%s"(host, port);
		}

		override void blocking(bool b)
		{
			if (!b)
			{
				assert(false, "TODO: TLS `blocking = false` not implemented.");
			}
		}

		override bool blocking()
		{
			return true;
		}

		override void send(string buffer)
		{
			while (!buffer.empty)
			{
				size_t result = BIO_write(this.bio, buffer.ptr, cast(int) buffer.length)
					.checkOpensslError!"could not write %s bytes to BIO"(buffer.length);

				buffer = buffer.drop(result);
			}
		}

		override size_t receive(char[] buffer)
		{
			return BIO_read(this.bio, cast(void*) buffer.ptr, cast(int) buffer.length)
				.checkOpensslError!"could not read (up to) %s bytes from BIO"(buffer.length);
		}

		override void close() @nogc nothrow
		{
			scope close = cast(void delegate() @nogc nothrow) {
				BIO_ssl_shutdown(this.bio);
				BIO_free_all(this.bio);
				X509_free(this.certificate);
				if (redisCertificateAuthority !is null)
				{
					X509_free(this.redisCertificateAuthority);
				}
				EVP_PKEY_free(this.privateKey);
			};
			close();
		}
	}

	private long checkOpensslError(string fmt, T...)(long returnCode, T args)
	out (result; result > 0)
	{
		import std.conv : to;
		import std.exception : enforce;
		enforce!ConnectionException(returnCode > 0,
			format!(fmt ~ ": %s")(args, ERR_error_string(ERR_get_error, null).to!string));
		return returnCode;
	}
}

/**
 * Sends a pre-encoded string
 *
 * Params:
 *   conn     	 = Connection to redis server.
 *   encoded_cmd = The command to be sent.
 *
 * Throws: $(D ConnectionException) if sending fails.
 */
void send(Transport conn, string encoded_cmd)
{
	debug(tinyredis) writeln("Request : '", escape(encoded_cmd), "'");

	conn.send(encoded_cmd);
}

/**
 * Receive responses from redis server
 *
 * Params:
 *   conn    	  = Connection to redis server.
 *   minResponses = The number of multibulks you expect
 *
 * Throws: $(D ConnectionException) if there is a socket error or server closes the connection.
 */
Response[] receiveResponses(Transport conn, size_t minResponses = 0)
{
	import std.array : back, popBack;

	char[] buffer;
	Response[] responses;

	Response*[] MultiBulks; //Stack of pointers to multibulks
	Response[]* stackPtr = &responses; // This is the stack where new elements are pushed

	for(;;)
	{
		receive(conn, buffer);

		while(buffer.length)
		{
			auto r = Response.parse(buffer);
			if(r.type == ResponseType.Invalid) // This occurs when the buffer is incomplete. Pull more
				break;

			*stackPtr ~= r;
			if(r.type == ResponseType.MultiBulk && r.count > 0)
			{
				auto mb = &(*stackPtr)[$-1];
				MultiBulks ~= mb;
				stackPtr = &(*mb).values;
			}

			while(MultiBulks.length)
			{
				auto mb = *MultiBulks.back;

				if(mb.count != mb.values.length)
					break;

				MultiBulks.popBack();
				stackPtr = MultiBulks.length ? &(*MultiBulks.back).values : &responses;
			}
		}

		if(buffer.length == 0 && MultiBulks.length == 0) //Make sure all the multi bulks got their data
		{
			debug(tinyredis)
				if(minResponses > 1 && responses.length < minResponses)
					writeln("WAITING FOR MORE RESPONSES ... ");

			if(responses.length >= minResponses)
				break;
		}
	}

	return responses;
}

/* -------- EXCEPTIONS ------------- */

class ConnectionException : Exception {
	mixin basicExceptionCtors;
}

private void receive(Transport conn, ref char[] buffer)
{
	import core.stdc.errno;
	import std.string : format;

	char[16 << 10] buff = void;
	size_t len = conn.receive(buff);

	buffer ~= buff[0 .. len];
	debug(tinyredis) writeln("Response : '", escape(cast(string)buffer), "'", " Length : ", len);
}
