
--luasocket-based scheduler for Lua coroutines.
--Cosmin Apreutesei. Public domain.

local socket = require'socket'
local glue = require'glue'

--assert the result of coroutine.resume(). on error, raise an error with the
--traceback of the not-yet unwound stack.
local function assert_resume(thread, ok, ...)
	if ok then return ... end
	error(debug.traceback(thread, ...), 3)
end

--create a new socket loop, dispatching to Lua coroutines or,
--to symmetric coroutines, if coro module given (coro = require'coro').
local function new(coro)

	local loop = {}

	local read, write = {}, {} --{skt: thread}

	local wait
	if coro then
		function wait(rwt,skt)
			rwt[skt] = coro.current
			coro.transfer(loop.thread)
			rwt[skt] = nil
		end
	else
		function wait(rwt,skt)
			rwt[skt] = coroutine.running()
			coroutine.yield()
			rwt[skt] = nil
		end
	end

	local function accept(skt,...)
		wait(read,skt)
		return assert(skt:accept(...))
	end

	local function receive(skt, patt, prefix)
		wait(read,skt)
		local s, err, partial = skt:receive(patt, prefix)
		if not s and err == 'timeout' then
			return receive(skt, patt, partial)
		else
			return s, err, partial
		end
	end

	local function send(skt,...)
		wait(write,skt)
		return skt:send(...)
	end

	local function close(skt,...)
		write[skt] = nil
		read[skt] = nil
		return assert(skt:close(...))
	end

	local function connect(skt, ...)
		assert(skt:settimeout(0,'b'))
		assert(skt:settimeout(0,'t'))
		local res, err = skt:connect(...)
		while res == nil do
			if err == 'already connected' then
				break
			end
			if err ~= 'timeout' and not err:find'in progress$' then
				return nil, err
			end
			wait(write, skt)
			res, err = skt:connect(...)
		end
		return loop.wrap(skt)
	end

	--wrap a luasocket socket object into an object that performs socket
	--operations asynchronously.
	function loop.wrap(skt)
		local o = {socket = skt}
		--set async methods
		function o:accept(...) return loop.wrap(accept(skt,...)) end
		function o:receive(...) return receive(skt,...) end
		function o:send(...) return send(skt,...) end
		function o:close(...) return close(skt,...) end
		function o:connect(...) return connect(skt,...) end
		--forward other methods to skt
		local mt = getmetatable(skt).__index
		for name, method in pairs(mt) do
			if type(method) == 'function' and not o[name] then
				o[name] = function(self, ...)
					return method(skt, ...)
				end
			end
		end
		return o
	end

	function loop.connect(address, port, locaddr, locport)
		local skt = assert(socket.tcp())
		if locaddr or locport then
			assert(skt:bind(locaddr, locport or 0))
		end
		skt = loop.wrap(skt)
		return skt:connect(address, port)
	end

	local function wake(skt,rwt)
		local thread = rwt[skt]
		if not thread then return end
		if coro then
			coro.transfer(thread)
		else
			assert_resume(thread, coroutine.resume(thread))
		end
		--thread yielded back here either because it asked for a read or write or
		--because it finished execution. finishing implies closing the connection.
		if not read[skt] and not write[skt] then
			skt:close()
		end
	end

	--call select() and resume the calling threads of the sockets that get loaded.
	function loop.dispatch(timeout)
		if not next(read) and not next(write) then return end
		local reads, writes, err = glue.keys(read), glue.keys(write)
		reads, writes, err = socket.select(reads, writes, timeout)
		if coro then
			loop.thread = coro.current
		end
		for i=1,#reads do wake(reads[i], read) end
		for i=1,#writes do wake(writes[i], write) end
		return true
	end

	local stop = false
	function loop.stop() stop = true end
	function loop.start(timeout)
		while loop.dispatch(timeout) do
			if stop then break end
		end
	end

	--create a coroutine or a coro thread set up to transfer control to the
	--loop thread on finish, and run it. return it while suspended in the first
	--socket call. dispatch() will manage it next.
	function loop.newthread(handler, args)
		if coro then
			local loop_thread = loop.thread
			local thread = coro.create(handler, loop_thread)
			loop.thread = coro.current
			coro.transfer(thread, args)
			loop.thread = loop_thread
			return thread
		else
			local thread = coroutine.create(function(args)
				local ok, err = glue.pcall(handler, args)
				if ok then return ok end
				error(err, 2)
			end)
			assert_resume(thread, coroutine.resume(thread, args))
		end
	end

	function loop.newserver(host, port, handler)
		local server_skt = socket.tcp()
		server_skt:settimeout(0)
		assert(server_skt:bind(host, port))
		assert(server_skt:listen(16384))
		server_skt = loop.wrap(server_skt)
		local function server()
			while true do
				local client_skt = server_skt:accept()
				loop.newthread(handler, client_skt)
			end
		end
		if coro then
			coro.transfer(coro.create(server))
		else
			loop.newthread(server)
		end
	end

	return loop
end

if not ... then require'socketloop_test' end

return new
